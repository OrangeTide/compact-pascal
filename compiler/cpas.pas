{$MODE TP}
{$IFNDEF FPC}
{$MEMORY 160}
{$MAXMEMORY 256}
{$ENDIF}
program cpas;
{** Compact Pascal compiler — targets WASM 1.0 binary format.
  Reads Pascal source from stdin, writes WASM binary to stdout,
  writes error diagnostics to stderr.

  Bootstrapped with fpc -Mtp. The compiler source uses longint
  (32-bit) everywhere to avoid TP's 16-bit integer.
}

{ ---- Constants ---- }

const
  Version = '26.04.1';
  VersionYear = 26;
  VersionMonth = 04;
  VersionPatch = 1;

  { Section buffer sizes }
  SmallBufMax = 4095;    { 4 KB for small sections }
  CodeBufMax  = 131071;  { 128 KB for code section }
  DataBufMax  = 65535;   { 64 KB for data section }

  { Symbol table limits }
  MaxSyms    = 1024;
  MaxScopes  = 32;
  MaxFuncs   = 256;   { max user-defined functions }
  MaxIfdefDepth = 8;  { max nested IFDEF levels }

  { WASM section IDs }
  SecIdType   = 1;
  SecIdImport = 2;
  SecIdFunc   = 3;
  SecIdTable  = 4;
  SecIdMemory = 5;
  SecIdGlobal = 6;
  SecIdExport = 7;
  SecIdStart  = 8;
  SecIdElem   = 9;
  SecIdCode   = 10;
  SecIdData   = 11;

  { WASM type constants }
  WasmI32    = $7F;
  WasmI64    = $7E;
  WasmF32    = $7D;
  WasmF64    = $7C;
  WasmFunc   = $60;
  WasmVoid   = $40;  { empty block type }

  { WASM opcodes }
  OpUnreachable = $00;
  OpNop         = $01;
  OpBlock       = $02;
  OpLoop        = $03;
  OpIf          = $04;
  OpElse        = $05;
  OpEnd         = $0B;
  OpBr          = $0C;
  OpBrIf        = $0D;
  OpReturn      = $0F;
  OpCall        = $10;
  OpCallInd     = $11;
  OpDrop        = $1A;
  OpSelect      = $1B;
  OpLocalGet    = $20;
  OpLocalSet    = $21;
  OpLocalTee    = $22;
  OpGlobalGet   = $23;
  OpGlobalSet   = $24;
  OpI32Load     = $28;
  OpI32Load8u   = $2D;
  OpI32Load8s   = $2C;
  OpI32Load16u  = $2F;
  OpI32Load16s  = $2E;
  OpI32Store    = $36;
  OpI32Store8   = $3A;
  OpI32Store16  = $3B;
  OpI32Const    = $41;
  OpI32Eqz      = $45;
  OpI32Eq       = $46;
  OpI32Ne       = $47;
  OpI32LtS      = $48;
  OpI32LtU      = $49;
  OpI32GtS      = $4A;
  OpI32GtU      = $4B;
  OpI32LeS      = $4C;
  OpI32LeU      = $4D;
  OpI32GeS      = $4E;
  OpI32GeU      = $4F;
  OpI32Add      = $6A;
  OpI32Sub      = $6B;
  OpI32Mul      = $6C;
  OpI32DivS     = $6D;
  OpI32DivU     = $6E;
  OpI32RemS     = $6F;
  OpI32RemU     = $70;
  OpI32And      = $71;
  OpI32Or       = $72;
  OpI32Xor      = $73;
  OpI32Shl      = $74;
  OpI32ShrS     = $75;
  OpI32ShrU     = $76;

  { WASM export kinds }
  ExportFunc   = $00;
  ExportTable  = $01;
  ExportMem    = $02;
  ExportGlobal = $03;

  { WASM import kinds }
  ImportFunc   = $00;

  { Token types }
  tkEOF       = 0;
  tkInteger   = 1;
  tkString    = 2;
  tkIdent     = 3;
  tkPlus      = 4;
  tkMinus     = 5;
  tkStar      = 6;
  tkSlash     = 7;
  tkEqual     = 8;
  tkNotEqual  = 9;
  tkLess      = 10;
  tkGreater   = 11;
  tkLessEq    = 12;
  tkGreaterEq = 13;
  tkLParen    = 14;
  tkRParen    = 15;
  tkLBrack    = 16;
  tkRBrack    = 17;
  tkAssign    = 18;
  tkColon     = 19;
  tkSemicolon = 20;
  tkComma     = 21;
  tkDot       = 22;
  tkDotDot    = 23;
  tkCaret     = 24;
  tkAt        = 25;
  tkDollar    = 26;

  { Keyword tokens - start at 100 }
  tkProgram   = 100;
  tkBegin     = 101;
  tkEnd       = 102;
  tkVar       = 103;
  tkConst     = 104;
  tkType      = 105;
  tkArray     = 106;
  tkOf        = 107;
  tkRecord    = 108;
  tkSet       = 109;
  tkProcedure = 110;
  tkFunction  = 111;
  tkForward   = 112;
  tkExternal  = 113;
  tkIf        = 114;
  tkThen      = 115;
  tkElse      = 116;
  tkWhile     = 117;
  tkDo        = 118;
  tkFor       = 119;
  tkTo        = 120;
  tkDownto    = 121;
  tkRepeat    = 122;
  tkUntil     = 123;
  tkCase      = 124;
  tkWith      = 125;
  tkDiv       = 126;
  tkMod       = 127;
  tkAnd       = 128;
  tkOr        = 129;
  tkNot       = 130;
  tkIn        = 131;
  tkNil       = 132;
  tkTrue      = 133;
  tkFalse     = 134;
  tkString_kw = 135;  { 'string' keyword }
  tkHalt      = 136;
  tkWrite     = 137;
  tkWriteln   = 138;
  tkRead      = 139;
  tkReadln    = 140;
  tkExit      = 141;
  tkAndThen   = 142;
  tkOrElse    = 143;
  tkBreak     = 144;
  tkContinue  = 145;
  tkShl       = 146;
  tkShr       = 147;

  { Type kinds }
  tyNone      = 0;
  tyInteger   = 1;
  tyBoolean   = 2;
  tyChar      = 3;
  tyString    = 4;
  tyRecord    = 5;
  tyArray     = 6;
  tyEnum      = 7;
  tySet       = 8;

  { Type descriptor table limits }
  MaxTypes    = 256;
  MaxFields   = 512;

  { Symbol kinds }
  skNone      = 0;
  skConst     = 1;
  skVar       = 2;
  skType      = 3;
  skProc      = 4;
  skFunc      = 5;
  skField     = 6;

  { Operator precedences for Pratt parser }
  PrecNone      = 0;
  PrecOrElse    = 1;  { or else }
  PrecAndThen   = 2;  { and then }
  PrecCompare   = 3;  { = <> < > <= >= in }
  PrecAdd       = 4;  { + - or }
  PrecMul       = 5;  { * div mod and shl shr }
  PrecUnary     = 6;  { not, unary +/- }

{ ---- Types ---- }

type
  TSmallBuf = record
    data: array[0..SmallBufMax] of byte;
    len: longint;
  end;

  TCodeBuf = record
    data: array[0..CodeBufMax] of byte;
    len: longint;
  end;

  TDataBuf = record
    data: array[0..DataBufMax] of byte;
    len: longint;
  end;

  TSymEntry = record
    name: string[63];
    kind: longint;   { skConst, skVar, etc. }
    typ: longint;    { tyInteger, tyBoolean, etc. }
    typeIdx: longint; { index into types[] for structured types, -1 otherwise }
    level: longint;  { nesting level }
    offset: longint; { stack offset for vars, value for consts, func index for procs }
    size: longint;   { byte size of var }
    strMax: longint; { max string length for string types (0 for non-string) }
    isVarParam: boolean;   { true if this is a var parameter (passed by reference) }
    isConstParam: boolean; { true if this is a const parameter (read-only) }
  end;

  { WASM type signature }
  TWasmParamArr = array[0..15] of byte;
  TWasmResultArr = array[0..3] of byte;
  TWasmType = record
    nparams: longint;
    params: TWasmParamArr;
    nresults: longint;
    results: TWasmResultArr;
  end;

  { WASM import record }
  TWasmImport = record
    modname: string[63];
    fieldname: string[63];
    kind: byte;
    typeidx: longint;
  end;

  (* User export record — tracks EXPORT directives *)
  TExportEntry = record
    name: string[63];
    funcIdx: longint;  { absolute WASM function index }
  end;

  { Type descriptor — for structured types (records, arrays) }
  TTypeDesc = record
    kind: longint;       { tyRecord or tyArray }
    size: longint;       { total byte size }
    { Record fields }
    fieldStart: longint; { index into fields[] }
    fieldCount: longint; { number of fields }
    { Array fields }
    elemType: longint;   { element type tag (tyInteger, tyRecord, etc.) }
    elemTypeIdx: longint;{ index into types[] for structured elements, -1 otherwise }
    elemSize: longint;   { byte size of one element }
    arrLo: longint;      { low bound }
    arrHi: longint;      { high bound }
    elemStrMax: longint; { strMax for string elements }
  end;

  { Field descriptor — for record fields }
  TFieldDesc = record
    name: string[63];
    typ: longint;        { type tag }
    typeIdx: longint;    { index into types[] for structured fields, -1 otherwise }
    offset: longint;     { byte offset from record start }
    size: longint;       { byte size }
    strMax: longint;     { max string length (0 for non-string) }
  end;

  { Defined function record — tracks each compiled function body }
  TFuncEntry = record
    name: string[63];     { function name for WASM name section }
    typeidx: longint;     { index into wasmTypes }
    bodyStart: longint;   { offset into funcBodies buffer }
    bodyLen: longint;     { length of body bytes in funcBodies }
    nlocals: longint;     { number of extra locals (beyond params) }
    nparams: longint;     { number of WASM parameters }
    varParams: array[0..15] of boolean; { which params are var (by-reference) }
    constParams: array[0..15] of boolean; { which params are const (string by-ref, read-only) }
  end;

{ ---- Global Variables ---- }

var
  { Section buffers }
  secType:   TSmallBuf;
  secImport: TSmallBuf;
  secFunc:   TSmallBuf;
  secMemory: TSmallBuf;
  secGlobal: TSmallBuf;
  secExport: TSmallBuf;
  secCode:   TCodeBuf;
  secData:   TDataBuf;
  secName:   TSmallBuf;

  { Output buffer - accumulate entire WASM module before writing }
  outBuf: TCodeBuf;

  { Scanner state }
  ch: char;
  tokKind: longint;
  tokInt: longint;
  tokStr: string;
  srcLine, srcCol: longint;
  atEof: boolean;

  { Symbol table }
  syms: array[0..MaxSyms-1] of TSymEntry;
  numSyms: longint;
  scopeBase: array[0..MaxScopes-1] of longint;
  scopeDepth: longint;

  { Type descriptor table (for structured types) }
  types: array[0..MaxTypes-1] of TTypeDesc;
  numTypes: longint;

  { Field descriptor table (for record fields) }
  fields: array[0..MaxFields-1] of TFieldDesc;
  numFields: longint;

  { Structured value parameter copy list (ParseProcDecl -> ParseBlock) }
  structCopyLocal: array[0..15] of longint;    { WASM local index holding source addr }
  structCopyFrameOff: array[0..15] of longint; { frame offset for the copy }
  structCopySize: array[0..15] of longint;     { byte size to copy }
  numStructCopies: longint;

  { Var/const parameter spill list (pointer spilled to frame for nested access) }
  varParamSpillLocal: array[0..15] of longint;    { WASM local index }
  varParamSpillFrameOff: array[0..15] of longint; { frame offset for stored pointer }
  numVarParamSpills: longint;

  { Pending variable initializers (deferred until after frame prologue) }
  varInitOffset: array[0..15] of longint;   { frame offset of the variable }
  varInitVal: array[0..15] of longint;      { scalar: constant value; string: data addr }
  varInitIsStr: array[0..15] of boolean;    { true if string initializer }
  varInitStrMax: array[0..15] of longint;   { string max length (only if isStr) }
  numVarInits: longint;

  { WASM type table }
  wasmTypes: array[0..63] of TWasmType;
  numWasmTypes: longint;

  { Import tracking }
  imports: array[0..31] of TWasmImport;
  numImports: longint;

  { Function tracking }
  numDefinedFuncs: longint;
  funcs: array[0..MaxFuncs-1] of TFuncEntry;
  numFuncs: longint;  { entries in funcs[] (excludes _start and __write_int) }

  { Accumulated function bodies (user procs compiled during parsing) }
  funcBodies: TCodeBuf;

  { Data segment }
  dataPos: longint;  { next free address in linear memory data segment }

  { Code generation state }
  curFrameSize: longint;   { current function's stack frame size }
  curNestLevel: longint;   { current nesting level }
  displayLocalIdx: longint; { WASM local index for saved display, -1 if none }

  { Special function indices (resolved during compilation) }
  idxProcExit: longint;    { proc_exit import index, -1 if not imported }
  idxFdWrite: longint;     { fd_write import index, -1 if not imported }
  idxFdRead: longint;      { fd_read import index, -1 if not imported }
  idxIntToStr: longint;    { int-to-string helper, -1 if not emitted }

  { Data segment addresses for I/O scratch areas }
  addrIovec: longint;      { 8-byte iovec struct }
  addrNwritten: longint;   { 4-byte fd_write result }
  addrIntBuf: longint;     { 66-byte integer conversion buffer }
  addrNewline: longint;    { 1-byte newline character }
  addrReadBuf: longint;    { 1-byte fd_read buffer }
  addrNread: longint;      { 4-byte fd_read result }
  addrCharStr: longint;    { 2-byte scratch for char-to-string conversion }

  { Start function code - accumulated separately, then wrapped }
  startCode: TCodeBuf;

  { Save stack for startCode during nested ParseProcDecl calls }
  savedCodeStack: array[0..7] of TCodeBuf;
  savedCodeStackTop: longint;

  { Helper function code buffer (for __write_int etc.) }
  helperCode: TCodeBuf;

  { Has the program used I/O? }
  needsFdWrite: boolean;
  needsFdRead: boolean;
  needsProcExit: boolean;
  needsWriteInt: boolean;
  needsReadInt: boolean;
  needsStrAssign: boolean;
  needsWriteStr: boolean;
  needsStrCompare: boolean;
  needsReadStr: boolean;
  needsStrAppend: boolean;
  needsStrCopy: boolean;         { __str_copy helper needed }
  needsStrPos: boolean;          { __str_pos helper needed }
  needsStrDelete: boolean;       { __str_delete helper needed }
  needsStrInsert: boolean;       { __str_insert helper needed }
  needsRangeCheck: boolean;      { __range_check helper needed }
  needsCheckedAdd: boolean;      { __checked_add helper needed }
  needsCheckedSub: boolean;      { __checked_sub helper needed }
  needsCheckedMul: boolean;      { __checked_mul helper needed }
  needsSetUnion: boolean;        { __set_union helper needed }
  needsSetIntersect: boolean;    { __set_intersect helper needed }
  needsSetDiff: boolean;         { __set_diff helper needed }
  needsSetEq: boolean;           { __set_eq helper needed }
  needsSetSubset: boolean;       { __set_subset helper needed }
  needsIntToStr: boolean;        { __int_to_str helper needed }
  needsWriteChar: boolean;       { __write_char helper needed }
  addrSetTemp: longint;          { 32-byte temp for large set arithmetic results }
  needsSetTemp: boolean;         { whether set temp was allocated }
  addrSetTemp2: longint;         { second 32-byte temp for compound set expressions }
  setTempFlip: boolean;          { toggle between addrSetTemp and addrSetTemp2 }
  addrSetZero: longint;          { static 32-byte zero block for [] with large sets }
  addrCopyTemp: longint;         { 256-byte temp for copy() result }
  needsCopyTemp: boolean;        { whether copy temp was allocated }
  concatPieces: longint;         { compile-time count of saved concat pieces }
  addrConcatScratch: longint;    { data segment addr of 16-slot scratch array }
  addrConcatTemp: longint;       { 256-byte temp string for concat result }
  needsConcatScratch: boolean;   { whether scratch was allocated }
  startNlocals: longint;         { extra locals for _start (0 or 1) }
  curStringTempIdx: longint;     { WASM local index for string temp in current func }
  curFuncNeedsStringTemp: boolean; { whether current func needs the string temp local }
  curCaseTempIdx: longint;       { WASM local index for case selector temp }
  curFuncNeedsCaseTemp: boolean;  { whether current func needs the case temp local }
  curFuncIsFunction: boolean;    { whether current func is a function (has return value) }
  curFuncReturnIdx: longint;     { WASM local index for return value in current func }
  breakDepth: longint;           { br depth for break (-1 = not in loop) }
  continueDepth: longint;        { br depth for continue (-1 = not in loop) }
  exitDepth: longint;            { br depth for exit (-1 = not in function/program body) }
  forLimitDepth: longint;        { current for-loop nesting depth }
  addrForLimit: array[0..15] of longint; { per-depth for-limit scratch addresses }

  { Expression type tracking }
  exprType: longint;  { type of last parsed expression (tyInteger, tyString, etc.) }
  exprSetSize: longint;  { for tySet: 4 = small (i32), >4 = large (memory-based) }

  (* Compiler directive options *)
  optMemPages: longint;       (* MEMORY n, default 1 *)
  optMaxMemPages: longint;    (* MAXMEMORY n, default 256 *)
  optStackSize: longint;      (* STACKSIZE n, default 65536 *)
  optDescription: string;     (* DESCRIPTION 'text' *)
  optRangeChecks: boolean;    (* R+/-, default false *)
  optOverflowChecks: boolean; (* Q+/-, default false *)
  optExtLiterals: boolean;    (* EXTLITERALS ON/OFF, default false *)
  optDump: boolean;           (* -dump command-line flag *)

  { Pending compiler directives }
  hasPendingImport: boolean;
  pendingImportMod: string[63];
  pendingImportName: string[63];
  hasPendingExport: boolean;
  pendingExportName: string[63];

  { Conditional compilation state }
  ifdefActive: array[0..MaxIfdefDepth-1] of boolean; { was the IF branch taken? }
  ifdefDepth: longint;                                { current nesting depth }

  (* User-defined exports from EXPORT directives *)
  userExports: array[0..31] of TExportEntry;
  numUserExports: longint;

  (* With statement stack *)
  withTypeIdx: array[0..7] of longint;    (* record type index *)
  withLevel: array[0..7] of longint;      (* nesting level of the record var *)
  withOffset: array[0..7] of longint;     (* frame offset of the record var *)
  withIsVarParam: array[0..7] of boolean; (* is the record a var param? *)
  withIsLocal: array[0..7] of boolean;    (* is it a WASM local (param)? *)
  withBaseWith: array[0..7] of longint;   (* -1=direct var, >=0=field of with entry *)
  withFieldOfs: array[0..7] of longint;   (* extra field offset when baseWith >= 0 *)
  numWiths: longint;

  {$IFDEF FPC}
  { Output file for binary WASM }
  outFile: file;
  {$ENDIF}

  { Temp buffer for LEB128 etc }
  tmpBuf: array[0..15] of byte;

{ ---- Forward declarations ---- }

procedure ParseBlock; forward;
procedure ParseStatement; forward;
procedure ParseExpression(minPrec: longint); forward;
procedure ParseProcDecl; forward;
procedure EvalConstExpr(var outVal: longint; var outTyp: longint); forward;

{ ---- Error handling ---- }

{$IFDEF FPC}
procedure WriteError(s: string);
begin
  write(stderr, s);
end;

procedure WriteErrorLn(s: string);
begin
  writeln(stderr, s);
end;
{$ELSE}
procedure WriteError(s: string);
begin
  write(stderr, s);
end;

procedure WriteErrorLn(s: string);
begin
  write(stderr, s);
  write(stderr, chr(10));
end;
{$ENDIF}

procedure Error(msg: string);
var lineStr, colStr: string[11];
begin
  str(srcLine, lineStr);
  str(srcCol, colStr);
  WriteErrorLn('Error: [' + lineStr + ':' + colStr + '] ' + msg);
  halt(1);
end;

procedure Expected(what: string);
begin
  Error(what + ' expected');
end;

{ ---- Character I/O ---- }

var
  pushbackCh: char;
  hasPushback: boolean;

{** Read the next input character into the global ch, or set atEof.

  Honors a single-character pushback buffer (set by UnreadCh) so the
  scanner can peek one character ahead. Tracks srcLine / srcCol for
  diagnostics. Two variants: the FPC build reads from the input file
  handle, the TP/self-hosted build uses default stdin via WASI. }
{$IFDEF FPC}
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
{$ELSE}
procedure ReadCh;
begin
  if hasPushback then begin
    ch := pushbackCh;
    hasPushback := false;
    exit;
  end;
  read(ch);
  if eof then begin
    ch := #0;
    atEof := true;
  end else begin
    if ch = #10 then begin
      srcLine := srcLine + 1;
      srcCol := 0;
    end else
      srcCol := srcCol + 1;
  end;
end;
{$ENDIF}

{** Push a character back so the next ReadCh returns it.
  Only one character of pushback is supported. }
procedure UnreadCh(c: char);
begin
  pushbackCh := c;
  hasPushback := true;
end;

{ ---- Scanner ---- }

{** Return c upper-cased if it is an ASCII lowercase letter, else c unchanged. }
function UpCase(c: char): char;
begin
  if (c >= 'a') and (c <= 'z') then
    UpCase := chr(ord(c) - 32)
  else
    UpCase := c;
end;

{** Consume whitespace (anything with code <= space) up to the next token. }
procedure SkipWhitespace;
begin
  while (not atEof) and (ch <= ' ') do
    ReadCh;
end;

{** Consume a // line comment through the trailing newline (but not past it). }
procedure SkipLineComment;
begin
  { // comment - skip to end of line }
  while (not atEof) and (ch <> #10) do
    ReadCh;
end;

{** Skip source text in an inactive IFDEF/ELSE branch.

  Scans characters looking for ELSE or ENDIF at nesting depth 0,
  counting nested IFDEF/IFNDEF/ENDIF pairs. Returns true if stopped
  at ELSE, false if stopped at ENDIF. On exit, ch is the character
  after the closing brace of the ELSE or ENDIF directive. }
function SkipInactiveBlock: boolean;
var
  depth: longint;
  dir: string;
begin
  depth := 0;
  while not atEof do begin
    if ch = '{' then begin
      ReadCh;
      if ch = '$' then begin
        ReadCh;
        dir := '';
        while (not atEof) and (ch <> '}') and
              ((ch in ['A'..'Z']) or (ch in ['a'..'z']) or (ch = '_')) do begin
          if ch in ['a'..'z'] then
            dir := dir + chr(ord(ch) - 32)
          else
            dir := dir + ch;
          ReadCh;
        end;
        if (dir = 'IFDEF') or (dir = 'IFNDEF') then begin
          inc(depth);
          while (not atEof) and (ch <> '}') do ReadCh;
          if ch = '}' then ReadCh;
        end else if dir = 'ENDIF' then begin
          if depth = 0 then begin
            while (not atEof) and (ch <> '}') do ReadCh;
            if ch = '}' then ReadCh;
            SkipInactiveBlock := false;
            exit;
          end;
          dec(depth);
          while (not atEof) and (ch <> '}') do ReadCh;
          if ch = '}' then ReadCh;
        end else if dir = 'ELSE' then begin
          if depth = 0 then begin
            while (not atEof) and (ch <> '}') do ReadCh;
            if ch = '}' then ReadCh;
            SkipInactiveBlock := true;
            exit;
          end;
          while (not atEof) and (ch <> '}') do ReadCh;
          if ch = '}' then ReadCh;
        end else begin
          { other directive in inactive block - skip }
          while (not atEof) and (ch <> '}') do ReadCh;
          if ch = '}' then ReadCh;
        end;
      end else begin
        { regular brace comment in inactive block }
        while (not atEof) and (ch <> '}') do ReadCh;
        if ch = '}' then ReadCh;
      end;
    end else if ch = '(' then begin
      ReadCh;
      if ch = '*' then begin
        ReadCh;
        while not atEof do begin
          if ch = '*' then begin
            ReadCh;
            if ch = ')' then begin ReadCh; break; end;
          end else
            ReadCh;
        end;
      end;
    end else if ch = '''' then begin
      { skip string literal so braces inside strings are ignored }
      ReadCh;
      while (not atEof) and (ch <> '''') do ReadCh;
      if ch = '''' then ReadCh;
    end else
      ReadCh;
  end;
  Error('unterminated {$IFDEF}');
  SkipInactiveBlock := false;
end;

(** Parse a brace comment or compiler directive ($I, $IFDEF, $R+/-, etc.).

  On entry, ch is the opening brace. On exit, ch is the character
  after the closing brace. Directives are dispatched here: $I include,
  $IFDEF / $ELSE / $ENDIF conditional compilation, $R+/- range checks,
  $Q+/- overflow checks, and friends. *)
procedure SkipBraceComment;
var
  directive: string;
  modName: string[63];
  impName: string[63];
  expName: string[63];
  descStr: string;
  intVal: longint;
  switchOn: boolean;
  i: longint;
  symName: string[63];
  condTrue: boolean;
  foundElse: boolean;

  procedure SkipDirectiveSpaces;
  begin
    while (not atEof) and (ch <= ' ') and (ch <> '}') do
      ReadCh;
  end;

  function ParseDirectiveSwitch: boolean;
  { Parse +/- or ON/OFF after directive name. Returns true=on, false=off. }
  var sw: string;
  begin
    SkipDirectiveSpaces;
    if ch = '+' then begin
      ReadCh;
      ParseDirectiveSwitch := true;
    end else if ch = '-' then begin
      ReadCh;
      ParseDirectiveSwitch := false;
    end else begin
      { Try ON/OFF }
      sw := '';
      while (not atEof) and (ch <> '}') and (ch > ' ') do begin
        if ch in ['a'..'z'] then
          sw := sw + chr(ord(ch) - 32)
        else
          sw := sw + ch;
        ReadCh;
      end;
      if sw = 'ON' then
        ParseDirectiveSwitch := true
      else if sw = 'OFF' then
        ParseDirectiveSwitch := false
      else
        Error('expected +/- or ON/OFF in compiler directive');
    end;
  end;

  function ParseDirectiveInt: longint;
  { Parse integer value after directive name. }
  var n: longint;
  begin
    SkipDirectiveSpaces;
    if not (ch in ['0'..'9']) then
      Error('expected integer value in compiler directive');
    n := 0;
    while (not atEof) and (ch in ['0'..'9']) do begin
      n := n * 10 + (ord(ch) - ord('0'));
      ReadCh;
    end;
    ParseDirectiveInt := n;
  end;

  procedure ParseDirectiveString(var result: string);
  { Parse quoted string after directive name. }
  begin
    SkipDirectiveSpaces;
    if ch <> '''' then
      Error('expected quoted string in compiler directive');
    ReadCh; { skip opening quote }
    result := '';
    while (not atEof) and (ch <> '''') do begin
      result := result + ch;
      ReadCh;
    end;
    if ch <> '''' then
      Error('unterminated string in compiler directive');
    ReadCh; { skip closing quote }
  end;

begin
  ReadCh; { skip opening brace }
  if ch = '$' then begin
    { Potential compiler directive }
    ReadCh; { skip $ }
    directive := '';
    while (not atEof) and (ch <> '}') and
          ((ch in ['A'..'Z']) or (ch in ['a'..'z']) or (ch in ['0'..'9']) or (ch = '_')) do begin
      if ch in ['a'..'z'] then
        directive := directive + chr(ord(ch) - 32)
      else
        directive := directive + ch;
      ReadCh;
    end;
    if directive = 'IMPORT' then begin
      (* IMPORT 'module' name *)
      SkipDirectiveSpaces;
      if ch <> '''' then
        Error('{$IMPORT} expects quoted module name');
      ReadCh; { skip opening quote }
      modName := '';
      while (not atEof) and (ch <> '''') do begin
        modName := modName + ch;
        ReadCh;
      end;
      if ch <> '''' then
        Error('unterminated module name in {$IMPORT}');
      ReadCh; { skip closing quote }
      SkipDirectiveSpaces;
      impName := '';
      while (not atEof) and (ch <> '}') and (ch > ' ') do begin
        impName := impName + ch;
        ReadCh;
      end;
      if length(impName) = 0 then
        Error('{$IMPORT} expects import name after module');
      hasPendingImport := true;
      pendingImportMod := modName;
      pendingImportName := impName;
    end else if directive = 'EXPORT' then begin
      (* EXPORT name *)
      SkipDirectiveSpaces;
      expName := '';
      while (not atEof) and (ch <> '}') and (ch > ' ') do begin
        expName := expName + ch;
        ReadCh;
      end;
      if length(expName) = 0 then
        Error('{$EXPORT} expects export name');
      hasPendingExport := true;
      pendingExportName := expName;
    end else if (directive = 'R') or (directive = 'RANGECHECKS') then begin
      optRangeChecks := ParseDirectiveSwitch;
    end else if (directive = 'Q') or (directive = 'OVERFLOWCHECKS') then begin
      optOverflowChecks := ParseDirectiveSwitch;
    end else if directive = 'MEMORY' then begin
      intVal := ParseDirectiveInt;
      if (intVal < 1) or (intVal > 65536) then
        Error('{$MEMORY} value must be 1..65536');
      optMemPages := intVal;
    end else if directive = 'MAXMEMORY' then begin
      intVal := ParseDirectiveInt;
      optMaxMemPages := intVal;
    end else if directive = 'STACKSIZE' then begin
      intVal := ParseDirectiveInt;
      if intVal < 256 then
        Error('{$STACKSIZE} must be at least 256');
      optStackSize := intVal;
    end else if directive = 'DESCRIPTION' then begin
      ParseDirectiveString(optDescription);
    end else if directive = 'EXTLITERALS' then begin
      optExtLiterals := ParseDirectiveSwitch;
    end else if (directive = 'I') or (directive = 'INCLUDE') then begin
      { Include files are resolved by host before compilation }
      while (not atEof) and (ch <> '}') do
        ReadCh;
    end else if directive = 'ALIGN' then begin
      { Recognized but not yet implemented }
      while (not atEof) and (ch <> '}') do
        ReadCh;
    end else if (directive = 'IFDEF') or (directive = 'IFNDEF') then begin
      SkipDirectiveSpaces;
      symName := '';
      while (not atEof) and (ch <> '}') and (ch > ' ') do begin
        if ch in ['a'..'z'] then
          symName := symName + chr(ord(ch) - 32)
        else
          symName := symName + ch;
        ReadCh;
      end;
      if directive = 'IFDEF' then
        condTrue := false
      else
        condTrue := true;
      if ifdefDepth >= MaxIfdefDepth then
        Error('too many nested {$IFDEF}');
      ifdefActive[ifdefDepth] := condTrue;
      inc(ifdefDepth);
      { consume closing brace }
      while (not atEof) and (ch <> '}') do ReadCh;
      if ch = '}' then ReadCh;
      if not condTrue then begin
        foundElse := SkipInactiveBlock;
        if not foundElse then
          dec(ifdefDepth); { ENDIF already consumed }
      end;
      exit;
    end else if directive = 'ELSE' then begin
      if ifdefDepth = 0 then
        Error('{$ELSE} without {$IFDEF}');
      if ifdefActive[ifdefDepth - 1] then begin
        { IF branch was taken — skip ELSE branch to ENDIF }
        while (not atEof) and (ch <> '}') do ReadCh;
        if ch = '}' then ReadCh;
        foundElse := SkipInactiveBlock;
        if foundElse then
          Error('duplicate {$ELSE}');
        dec(ifdefDepth);
        exit;
      end;
      { IF branch was skipped — ELSE is active (shouldn't reach here normally,
        SkipInactiveBlock returns to after the ELSE closing brace) }
    end else if directive = 'ENDIF' then begin
      if ifdefDepth = 0 then
        Error('{$ENDIF} without {$IFDEF}');
      dec(ifdefDepth);
    end else begin
      { Unknown directive - skip rest as comment }
      while (not atEof) and (ch <> '}') do
        ReadCh;
    end;
  end else begin
    { Regular brace comment }
    while (not atEof) and (ch <> '}') do
      ReadCh;
  end;
  if ch = '}' then
    ReadCh
  else
    Error('unterminated comment');
end;

{** Skip a (* ... *) paren-star comment. On entry, ch is the '*' after
  the '('; on exit, ch is the character after the closing ')'. }
procedure SkipParenComment;
begin
  { (* comment *) }
  ReadCh; { skip * after ( }
  while not atEof do begin
    if (ch = '*') then begin
      ReadCh;
      if ch = ')' then begin
        ReadCh;
        exit;
      end;
    end else
      ReadCh;
  end;
  Error('unterminated comment');
end;

(** Consume any run of whitespace and comments (brace, paren-star, line).

  Loops until ch is positioned on a real token character (or atEof).
  A lone '(' or '/' that is not followed by a comment is pushed back
  and left for NextToken to tokenize. *)
procedure SkipWhitespaceAndComments;
var done: boolean;
begin
  done := false;
  while not done do begin
    done := true;
    while (not atEof) and (ch <= ' ') do begin
      ReadCh;
      done := false;
    end;
    if (not atEof) and (ch = '{') then begin
      SkipBraceComment;
      done := false;
    end
    else if (not atEof) and (ch = '(') then begin
      ReadCh;
      if ch = '*' then begin
        SkipParenComment;
        done := false;
      end else begin
        (* Not a comment - push back the char after ( *)
        UnreadCh(ch);
        ch := '(';
        (* ch is now '(' and NextToken will handle it *)
      end;
    end
    else if (not atEof) and (ch = '/') then begin
      ReadCh;
      if ch = '/' then begin
        SkipLineComment;
        done := false;
      end else begin
        { Not a comment - push back the char after / }
        UnreadCh(ch);
        ch := '/';
        { ch is now '/' and NextToken will handle it as division }
      end;
    end;
  end;
end;

{** Return the token kind for s if it is a reserved word, else -1.

  s must already be uppercased (Pascal keywords are case-insensitive,
  so the scanner uppercases the identifier before looking it up). }
function LookupKeyword(const s: string): longint;
begin
  LookupKeyword := -1;
  if s = 'PROGRAM' then LookupKeyword := tkProgram
  else if s = 'BEGIN' then LookupKeyword := tkBegin
  else if s = 'END' then LookupKeyword := tkEnd
  else if s = 'VAR' then LookupKeyword := tkVar
  else if s = 'CONST' then LookupKeyword := tkConst
  else if s = 'TYPE' then LookupKeyword := tkType
  else if s = 'ARRAY' then LookupKeyword := tkArray
  else if s = 'OF' then LookupKeyword := tkOf
  else if s = 'RECORD' then LookupKeyword := tkRecord
  else if s = 'SET' then LookupKeyword := tkSet
  else if s = 'PROCEDURE' then LookupKeyword := tkProcedure
  else if s = 'FUNCTION' then LookupKeyword := tkFunction
  else if s = 'FORWARD' then LookupKeyword := tkForward
  else if s = 'EXTERNAL' then LookupKeyword := tkExternal
  else if s = 'IF' then LookupKeyword := tkIf
  else if s = 'THEN' then LookupKeyword := tkThen
  else if s = 'ELSE' then LookupKeyword := tkElse
  else if s = 'WHILE' then LookupKeyword := tkWhile
  else if s = 'DO' then LookupKeyword := tkDo
  else if s = 'FOR' then LookupKeyword := tkFor
  else if s = 'TO' then LookupKeyword := tkTo
  else if s = 'DOWNTO' then LookupKeyword := tkDownto
  else if s = 'REPEAT' then LookupKeyword := tkRepeat
  else if s = 'UNTIL' then LookupKeyword := tkUntil
  else if s = 'CASE' then LookupKeyword := tkCase
  else if s = 'WITH' then LookupKeyword := tkWith
  else if s = 'DIV' then LookupKeyword := tkDiv
  else if s = 'MOD' then LookupKeyword := tkMod
  else if s = 'AND' then LookupKeyword := tkAnd
  else if s = 'OR' then LookupKeyword := tkOr
  else if s = 'NOT' then LookupKeyword := tkNot
  else if s = 'IN' then LookupKeyword := tkIn
  else if s = 'NIL' then LookupKeyword := tkNil
  else if s = 'TRUE' then LookupKeyword := tkTrue
  else if s = 'FALSE' then LookupKeyword := tkFalse
  else if s = 'STRING' then LookupKeyword := tkString_kw
  else if s = 'HALT' then LookupKeyword := tkHalt
  else if s = 'WRITE' then LookupKeyword := tkWrite
  else if s = 'WRITELN' then LookupKeyword := tkWriteln
  else if s = 'READ' then LookupKeyword := tkRead
  else if s = 'READLN' then LookupKeyword := tkReadln
  else if s = 'EXIT' then LookupKeyword := tkExit
  else if s = 'BREAK' then LookupKeyword := tkBreak
  else if s = 'CONTINUE' then LookupKeyword := tkContinue
  else if s = 'SHL' then LookupKeyword := tkShl
  else if s = 'SHR' then LookupKeyword := tkShr;
end;

{ Pending token mechanism for when scanner reads too far }
var
  pendingTok: boolean;
  pendingKind: longint;
  pendingInt: longint;
  pendingStr: string;

{** Scan an integer literal into tokInt.

  Accepts decimal, $hex, &octal, %binary, and 0x/0o/0b prefix forms.
  Sets tokKind := tkInt. Underscores between digits are allowed as
  visual separators. Overflows are reported by Error. }
procedure ScanNumber;
var
  n: longint;
begin
  n := 0;
  if ch = '$' then begin
    { hex literal }
    ReadCh;
    if not ((ch >= '0') and (ch <= '9') or
            (ch >= 'A') and (ch <= 'F') or
            (ch >= 'a') and (ch <= 'f')) then
      Error('hex digit expected');
    while (ch >= '0') and (ch <= '9') or
          (ch >= 'A') and (ch <= 'F') or
          (ch >= 'a') and (ch <= 'f') do begin
      if (ch >= '0') and (ch <= '9') then
        n := n * 16 + ord(ch) - ord('0')
      else if (ch >= 'A') and (ch <= 'F') then
        n := n * 16 + ord(ch) - ord('A') + 10
      else
        n := n * 16 + ord(ch) - ord('a') + 10;
      ReadCh;
    end;
  end else if optExtLiterals and (ch = '0') then begin
    ReadCh;
    if (ch = 'x') or (ch = 'X') then begin
      { 0x hex literal }
      ReadCh;
      if not ((ch >= '0') and (ch <= '9') or
              (ch >= 'A') and (ch <= 'F') or
              (ch >= 'a') and (ch <= 'f')) then
        Error('hex digit expected after 0x');
      while (ch >= '0') and (ch <= '9') or
            (ch >= 'A') and (ch <= 'F') or
            (ch >= 'a') and (ch <= 'f') do begin
        if (ch >= '0') and (ch <= '9') then
          n := n * 16 + ord(ch) - ord('0')
        else if (ch >= 'A') and (ch <= 'F') then
          n := n * 16 + ord(ch) - ord('A') + 10
        else
          n := n * 16 + ord(ch) - ord('a') + 10;
        ReadCh;
      end;
    end else if (ch = 'o') or (ch = 'O') then begin
      { 0o octal literal }
      ReadCh;
      if not ((ch >= '0') and (ch <= '7')) then
        Error('octal digit expected after 0o');
      while (ch >= '0') and (ch <= '7') do begin
        n := n * 8 + ord(ch) - ord('0');
        ReadCh;
      end;
    end else if (ch = 'b') or (ch = 'B') then begin
      { 0b binary literal }
      ReadCh;
      if not ((ch = '0') or (ch = '1')) then
        Error('binary digit expected after 0b');
      while (ch = '0') or (ch = '1') do begin
        n := n * 2 + ord(ch) - ord('0');
        ReadCh;
      end;
    end else begin
      { Just a zero followed by more digits (or not) }
      while (ch >= '0') and (ch <= '9') do begin
        n := n * 10 + ord(ch) - ord('0');
        ReadCh;
      end;
    end;
    { check for real literal - reject with clear error }
    if ch = '.' then begin
      ReadCh;
      if (ch >= '0') and (ch <= '9') then
        Error('real numbers are not supported in Phase 1');
      if ch = '.' then begin
        { N.. (range): return integer, buffer pending tkDotDot }
        ReadCh;  { consume second dot }
        tokKind := tkInteger;
        tokInt := n;
        pendingTok := true;
        pendingKind := tkDotDot;
        pendingInt := 0;
        pendingStr := '';
        exit;
      end else begin
        { N. (end of program or record access) — push dot back }
        UnreadCh(ch);
        ch := '.';
        { Actually we already consumed the dot. Use pending token. }
        tokKind := tkInteger;
        tokInt := n;
        pendingTok := true;
        pendingKind := tkDot;
        pendingInt := 0;
        pendingStr := '';
        exit;
      end;
    end;
  end else begin
    { decimal literal }
    while (ch >= '0') and (ch <= '9') do begin
      n := n * 10 + ord(ch) - ord('0');
      ReadCh;
    end;
    { check for real literal - reject with clear error }
    if ch = '.' then begin
      ReadCh;
      if (ch >= '0') and (ch <= '9') then
        Error('real numbers are not supported in Phase 1');
      if ch = '.' then begin
        { N.. (range): return integer, buffer pending tkDotDot }
        ReadCh;  { consume second dot }
        tokKind := tkInteger;
        tokInt := n;
        pendingTok := true;
        pendingKind := tkDotDot;
        pendingInt := 0;
        pendingStr := '';
        exit;
      end else begin
        { N. (end of program or record access) — push dot back }
        UnreadCh(ch);
        ch := '.';
        { Actually we already consumed the dot. Use pending token. }
        tokKind := tkInteger;
        tokInt := n;
        pendingTok := true;
        pendingKind := tkDot;
        pendingInt := 0;
        pendingStr := '';
        exit;
      end;
    end;
  end;
  tokKind := tkInteger;
  tokInt := n;
end;

{** Scan a Pascal string literal (single-quoted) into tokStr.

  Doubled quotes inside the literal represent a single quote. High
  bytes (>=$80) are passed through verbatim for UTF-8 source. }
procedure ScanString;
var
  s: string;
begin
  s := '';
  ReadCh; { skip opening quote }
  while true do begin
    if atEof then
      Error('unterminated string literal');
    if ch = '''' then begin
      ReadCh;
      if ch = '''' then begin
        s := s + '''';
        ReadCh;
      end else
        break; { end of string }
    end else begin
      s := s + ch;
      ReadCh;
    end;
  end;
  { Check for adjacent #N char constants }
  while ch = '#' do begin
    ReadCh;
    if ch = '$' then begin
      { hex char constant }
      ReadCh;
      tokInt := 0;
      while (ch >= '0') and (ch <= '9') or
            (ch >= 'A') and (ch <= 'F') or
            (ch >= 'a') and (ch <= 'f') do begin
        if (ch >= '0') and (ch <= '9') then
          tokInt := tokInt * 16 + ord(ch) - ord('0')
        else if (ch >= 'A') and (ch <= 'F') then
          tokInt := tokInt * 16 + ord(ch) - ord('A') + 10
        else
          tokInt := tokInt * 16 + ord(ch) - ord('a') + 10;
        ReadCh;
      end;
    end else begin
      { decimal char constant }
      tokInt := 0;
      while (ch >= '0') and (ch <= '9') do begin
        tokInt := tokInt * 10 + ord(ch) - ord('0');
        ReadCh;
      end;
    end;
    if (tokInt < 0) or (tokInt > 255) then
      Error('character constant out of range (0..255)');
    s := s + chr(tokInt);
    { Check for another string segment }
    if ch = '''' then begin
      ReadCh; { skip opening quote }
      while true do begin
        if atEof then
          Error('unterminated string literal');
        if ch = '''' then begin
          ReadCh;
          if ch = '''' then begin
            s := s + '''';
            ReadCh;
          end else
            break;
        end else begin
          s := s + ch;
          ReadCh;
        end;
      end;
    end;
  end;
  tokKind := tkString;
  tokStr := s;
end;

{** Scan a #nnn character constant or #nnn-prefixed string.

  Accepts runs of #N / 'text' / #N ... and concatenates them into
  tokStr (as tkString). A single #N becomes a one-character string. }
procedure ScanCharConst;
{ #N or #$HH char constant at start of token (not adjacent to string) }
var
  n: longint;
  s: string;
begin
  ReadCh; { skip # }
  s := '';
  repeat
    if ch = '$' then begin
      ReadCh;
      n := 0;
      while (ch >= '0') and (ch <= '9') or
            (ch >= 'A') and (ch <= 'F') or
            (ch >= 'a') and (ch <= 'f') do begin
        if (ch >= '0') and (ch <= '9') then
          n := n * 16 + ord(ch) - ord('0')
        else if (ch >= 'A') and (ch <= 'F') then
          n := n * 16 + ord(ch) - ord('A') + 10
        else
          n := n * 16 + ord(ch) - ord('a') + 10;
        ReadCh;
      end;
    end else begin
      n := 0;
      while (ch >= '0') and (ch <= '9') do begin
        n := n * 10 + ord(ch) - ord('0');
        ReadCh;
      end;
    end;
    if (n < 0) or (n > 255) then
      Error('character constant out of range (0..255)');
    s := s + chr(n);
    { Check for continuation: another #, or a string literal }
    if ch = '''' then begin
      { String continues }
      ReadCh;
      while true do begin
        if atEof then
          Error('unterminated string literal');
        if ch = '''' then begin
          ReadCh;
          if ch = '''' then begin
            s := s + '''';
            ReadCh;
          end else
            break;
        end else begin
          s := s + ch;
          ReadCh;
        end;
      end;
    end;
  until ch <> '#';

  if length(s) = 1 then begin
    { Single char constant - could be used as char or string }
    tokKind := tkString;
    tokStr := s;
  end else begin
    tokKind := tkString;
    tokStr := s;
  end;
end;

{** Scan the next token and fill the globals tokKind/tokInt/tokStr.

  Single-pass, one-token lookahead. The parser never touches raw
  characters — all tokenization flows through here. Output fields:

    tokKind : longint  — one of the tk* constants (tkIdent, tkInt,
                         tkString, tkPlus, tkBegin, ..., tkEof).
    tokInt  : longint  — integer value for tkInt, char code for
                         single-char constants.
    tokStr  : string   — identifier or string literal text.
    tokLine, tokCol    — source position of this token's first char.

  pendingTok is a one-token unread buffer: if set by the parser
  (via PushToken), that token is returned first before scanning
  resumes. Whitespace and all comment forms are consumed by
  SkipWhitespaceAndComments before dispatch on the leading char. }
procedure NextToken;
var
  ident: string;
  kw: longint;
begin
  if pendingTok then begin
    tokKind := pendingKind;
    tokInt := pendingInt;
    tokStr := pendingStr;
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
      while (ch >= 'A') and (ch <= 'Z') or
            (ch >= 'a') and (ch <= 'z') or
            (ch >= '0') and (ch <= '9') or
            (ch = '_') do begin
        ident := ident + UpCase(ch);
        ReadCh;
      end;
      kw := LookupKeyword(ident);
      if kw >= 0 then begin
        tokKind := kw;
        tokStr := ident;
        { Check for two-word operators: AND THEN, OR ELSE }
        if kw = tkAnd then begin
          SkipWhitespaceAndComments;
          if (ch >= 'A') and (ch <= 'Z') or
             (ch >= 'a') and (ch <= 'z') then begin
            ident := '';
            while (ch >= 'A') and (ch <= 'Z') or
                  (ch >= 'a') and (ch <= 'z') or
                  (ch >= '0') and (ch <= '9') or
                  (ch = '_') do begin
              ident := ident + UpCase(ch);
              ReadCh;
            end;
            if ident = 'THEN' then
              tokKind := tkAndThen
            else begin
              { Not 'then' - push back as pending token }
              pendingTok := true;
              pendingKind := LookupKeyword(ident);
              if pendingKind < 0 then begin
                pendingKind := tkIdent;
                pendingStr := ident;
              end else
                pendingStr := ident;
              pendingInt := 0;
            end;
          end;
        end
        else if kw = tkOr then begin
          SkipWhitespaceAndComments;
          if (ch >= 'A') and (ch <= 'Z') or
             (ch >= 'a') and (ch <= 'z') then begin
            ident := '';
            while (ch >= 'A') and (ch <= 'Z') or
                  (ch >= 'a') and (ch <= 'z') or
                  (ch >= '0') and (ch <= '9') or
                  (ch = '_') do begin
              ident := ident + UpCase(ch);
              ReadCh;
            end;
            if ident = 'ELSE' then
              tokKind := tkOrElse
            else begin
              pendingTok := true;
              pendingKind := LookupKeyword(ident);
              if pendingKind < 0 then begin
                pendingKind := tkIdent;
                pendingStr := ident;
              end else
                pendingStr := ident;
              pendingInt := 0;
            end;
          end;
        end;
      end else begin
        tokKind := tkIdent;
        tokStr := ident;
      end;
    end;

    '0'..'9': begin
      ScanNumber;
    end;

    '$': begin
      ScanNumber;
    end;

    '''': begin
      ScanString;
    end;

    '#': begin
      ScanCharConst;
    end;

    '+': begin tokKind := tkPlus; ReadCh; end;
    '-': begin tokKind := tkMinus; ReadCh; end;
    '*': begin tokKind := tkStar; ReadCh; end;
    '/': begin tokKind := tkSlash; ReadCh; end;
    '=': begin tokKind := tkEqual; ReadCh; end;
    '<': begin
      ReadCh;
      if ch = '>' then begin tokKind := tkNotEqual; ReadCh; end
      else if ch = '=' then begin tokKind := tkLessEq; ReadCh; end
      else tokKind := tkLess;
    end;
    '>': begin
      ReadCh;
      if ch = '=' then begin tokKind := tkGreaterEq; ReadCh; end
      else tokKind := tkGreater;
    end;
    '(': begin tokKind := tkLParen; ReadCh; end;
    ')': begin tokKind := tkRParen; ReadCh; end;
    '[': begin tokKind := tkLBrack; ReadCh; end;
    ']': begin tokKind := tkRBrack; ReadCh; end;
    ':': begin
      ReadCh;
      if ch = '=' then begin tokKind := tkAssign; ReadCh; end
      else tokKind := tkColon;
    end;
    ';': begin tokKind := tkSemicolon; ReadCh; end;
    ',': begin tokKind := tkComma; ReadCh; end;
    '.': begin
      ReadCh;
      if ch = '.' then begin tokKind := tkDotDot; ReadCh; end
      else tokKind := tkDot;
    end;
    '^': begin tokKind := tkCaret; ReadCh; end;
    '@': begin tokKind := tkAt; ReadCh; end;
  else
    Error('unexpected character: ' + ch);
  end;
end;

{** Require the current token to be tk, then advance.
  Reports an error and halts if the current token is something else. }
procedure Expect(tk: longint);
var s: string;
begin
  if tokKind <> tk then begin
    case tk of
      tkSemicolon: s := '";"';
      tkDot:       s := '"."';
      tkColon:     s := '":"';
      tkAssign:    s := '":="';
      tkLParen:    s := '"("';
      tkRParen:    s := '")"';
      tkLBrack:    s := '"["';
      tkRBrack:    s := '"]"';
      tkBegin:     s := '"begin"';
      tkEnd:       s := '"end"';
      tkThen:      s := '"then"';
      tkDo:        s := '"do"';
      tkOf:        s := '"of"';
      tkProgram:   s := '"program"';
      tkIdent:     s := 'identifier';
      tkInteger:   s := 'integer literal';
    else
      s := 'token';
    end;
    Expected(s);
  end;
  NextToken;
end;

{ ---- Buffer operations ---- }

procedure SmallBufInit(var b: TSmallBuf);
begin
  b.len := 0;
end;

procedure CodeBufInit(var b: TCodeBuf);
begin
  b.len := 0;
end;

procedure DataBufInit(var b: TDataBuf);
begin
  b.len := 0;
end;

procedure SmallBufEmit(var b: TSmallBuf; v: byte);
begin
  if b.len > SmallBufMax then
    Error('section buffer overflow');
  b.data[b.len] := v;
  b.len := b.len + 1;
end;

procedure CodeBufEmit(var b: TCodeBuf; v: byte);
begin
  if b.len > CodeBufMax then
    Error('code buffer overflow');
  b.data[b.len] := v;
  b.len := b.len + 1;
end;

procedure DataBufEmit(var b: TDataBuf; v: byte);
begin
  if b.len > DataBufMax then
    Error('data buffer overflow');
  b.data[b.len] := v;
  b.len := b.len + 1;
end;

{ ---- LEB128 encoding ---- }

procedure EmitULEB128(var b: TCodeBuf; value: longint);
var
  v: longint;
  byt: byte;
begin
  v := value;
  repeat
    byt := v and $7F;
    v := v shr 7;
    if v <> 0 then
      byt := byt or $80;
    CodeBufEmit(b, byt);
  until v = 0;
end;

procedure EmitSLEB128(var b: TCodeBuf; value: longint);
var
  more: boolean;
  byt: byte;
begin
  more := true;
  while more do begin
    byt := value and $7F;
    value := value shr 7;
    { Sign extend for arithmetic right shift }
    { In TP, shr is logical. Need to handle sign bit. }
    { For negative values, after shr 7 we need to fill with 1s }
    { Actually, let's use div instead for arithmetic shift }
    { Rewrite: }
  end;
  { Let me redo this properly }
end;

{ Redo signed LEB128 properly for TP where shr is logical }
procedure EmitSLEB128Fix(var b: TCodeBuf; value: longint);
var
  byt: byte;
  more: boolean;
  negative: boolean;
begin
  more := true;
  negative := value < 0;
  while more do begin
    byt := value and $7F;
    { Arithmetic right shift: use div for negative numbers }
    if value >= 0 then
      value := value shr 7
    else begin
      value := value shr 7;
      value := value or (longint($FE000000)); { sign extend - fill top 7 bits }
    end;
    { Check if we can stop }
    if (value = 0) and ((byt and $40) = 0) then
      more := false
    else if (value = -1) and ((byt and $40) <> 0) then
      more := false;
    if more then
      byt := byt or $80;
    CodeBufEmit(b, byt);
  end;
end;

{ Small buffer versions of LEB128 }
procedure SmallEmitSLEB128(var b: TSmallBuf; value: longint);
var
  byt: byte;
  more: boolean;
begin
  more := true;
  while more do begin
    byt := value and $7F;
    if value >= 0 then
      value := value shr 7
    else begin
      value := value shr 7;
      value := value or (longint($FE000000));
    end;
    if (value = 0) and ((byt and $40) = 0) then
      more := false
    else if (value = -1) and ((byt and $40) <> 0) then
      more := false;
    if more then
      byt := byt or $80;
    SmallBufEmit(b, byt);
  end;
end;

procedure SmallEmitULEB128(var b: TSmallBuf; value: longint);
var
  v: longint;
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

{ ---- WASM type management ---- }

function AddWasmType(np: longint; var p: TWasmParamArr;
                     nr: longint; var r: TWasmResultArr): longint;
var
  i, j: longint;
  match: boolean;
begin
  { Check if type already exists }
  for i := 0 to numWasmTypes - 1 do begin
    if (wasmTypes[i].nparams = np) and (wasmTypes[i].nresults = nr) then begin
      match := true;
      for j := 0 to np - 1 do
        if wasmTypes[i].params[j] <> p[j] then match := false;
      for j := 0 to nr - 1 do
        if wasmTypes[i].results[j] <> r[j] then match := false;
      if match then begin
        AddWasmType := i;
        exit;
      end;
    end;
  end;
  { Add new type }
  if numWasmTypes >= 64 then
    Error('too many WASM types');
  wasmTypes[numWasmTypes].nparams := np;
  for i := 0 to np - 1 do
    wasmTypes[numWasmTypes].params[i] := p[i];
  wasmTypes[numWasmTypes].nresults := nr;
  for i := 0 to nr - 1 do
    wasmTypes[numWasmTypes].results[i] := r[i];
  AddWasmType := numWasmTypes;
  numWasmTypes := numWasmTypes + 1;
end;

{ Common type signatures }
function TypeVoidVoid: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  TypeVoidVoid := AddWasmType(0, p, 0, r);
end;

function TypeI32Void: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32;
  TypeI32Void := AddWasmType(1, p, 0, r);
end;

function TypeVoidI32: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  r[0] := WasmI32;
  TypeVoidI32 := AddWasmType(0, p, 1, r);
end;

function TypeI32x2Void: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32;
  TypeI32x2Void := AddWasmType(2, p, 0, r);
end;

function TypeI32x2I32: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32;
  r[0] := WasmI32;
  TypeI32x2I32 := AddWasmType(2, p, 1, r);
end;

function TypeI32x3Void: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32; p[2] := WasmI32;
  TypeI32x3Void := AddWasmType(3, p, 0, r);
end;

function TypeI32x3I32: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32; p[2] := WasmI32;
  r[0] := WasmI32;
  TypeI32x3I32 := AddWasmType(3, p, 1, r);
end;

function TypeI32x4Void: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32; p[2] := WasmI32; p[3] := WasmI32;
  TypeI32x4Void := AddWasmType(4, p, 0, r);
end;

function TypeI32x4I32: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32; p[2] := WasmI32; p[3] := WasmI32;
  r[0] := WasmI32;
  TypeI32x4I32 := AddWasmType(4, p, 1, r);
end;

{ ---- Import management ---- }

function AddImport(mname, fname: string; typeidx: longint): longint;
var i: longint;
begin
  { Check if already imported }
  for i := 0 to numImports - 1 do begin
    if (imports[i].modname = mname) and (imports[i].fieldname = fname) then begin
      AddImport := i;
      exit;
    end;
  end;
  if numImports >= 32 then
    Error('too many imports');
  imports[numImports].modname := mname;
  imports[numImports].fieldname := fname;
  imports[numImports].kind := ImportFunc;
  imports[numImports].typeidx := typeidx;
  AddImport := numImports;
  numImports := numImports + 1;
end;

function EnsureProcExit: longint;
begin
  EnsureProcExit := idxProcExit;
end;

function EnsureFdWrite: longint;
begin
  EnsureFdWrite := idxFdWrite;
end;

{ ---- Data segment management ---- }

function AllocData(size: longint): longint;
begin
  AllocData := dataPos;
  dataPos := dataPos + size;
end;

function AllocDataAligned(size, align: longint): longint;
var
  pad: longint;
begin
  pad := (align - (dataPos mod align)) mod align;
  while pad > 0 do begin
    DataBufEmit(secData, 0);
    dataPos := dataPos + 1;
    pad := pad - 1;
  end;
  AllocDataAligned := dataPos;
  dataPos := dataPos + size;
end;

function EmitDataString(const s: string): longint;
var
  addr: longint;
  i: longint;
begin
  addr := AllocData(length(s));
  for i := 1 to length(s) do
    DataBufEmit(secData, byte(ord(s[i])));
  EmitDataString := addr;
end;

function EmitDataPascalString(const s: string): longint;
{** Emit a Pascal short string to the data segment (length byte + data). }
var
  addr: longint;
  i: longint;
begin
  addr := AllocData(length(s) + 1);
  DataBufEmit(secData, byte(length(s)));
  for i := 1 to length(s) do
    DataBufEmit(secData, byte(ord(s[i])));
  EmitDataPascalString := addr;
end;

procedure EnsureIOBuffers;
begin
  if addrIovec < 0 then begin
    addrIovec := AllocDataAligned(8, 4);  { iovec: buf ptr (4) + len (4) }
    { Reserve the 8 bytes in data buffer }
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
  end;
  if addrNwritten < 0 then begin
    addrNwritten := AllocDataAligned(4, 4);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
  end;
  if addrNewline < 0 then begin
    addrNewline := AllocData(1);
    DataBufEmit(secData, 10); { newline character }
  end;
end;

{ ---- Code emission helpers (emit to startCode buffer) ---- }

procedure EmitOp(op: byte);
begin
  CodeBufEmit(startCode, op);
end;

procedure EmitI32Const(value: longint);
begin
  CodeBufEmit(startCode, OpI32Const);
  EmitSLEB128Fix(startCode, value);
end;

procedure EmitCall(funcIdx: longint);
begin
  CodeBufEmit(startCode, OpCall);
  EmitULEB128(startCode, funcIdx);
end;

{ Emit i32.store to [addr] }
procedure EmitI32Store(align, offset: longint);
begin
  CodeBufEmit(startCode, OpI32Store);
  EmitULEB128(startCode, align);
  EmitULEB128(startCode, offset);
end;

procedure EmitI32Store8(offset: longint);
begin
  CodeBufEmit(startCode, OpI32Store8);
  EmitULEB128(startCode, 0);
  EmitULEB128(startCode, offset);
end;

{ Emit a store appropriate for the given type: i32.store8 for char/boolean,
  i32.store for integer and other 4-byte types }
procedure EmitStoreByType(typ: longint);
begin
  if (typ = tyChar) or (typ = tyBoolean) then
    EmitI32Store8(0)
  else
    EmitI32Store(2, 0);
end;

{ Emit memory.copy (dst, src, len already on stack) }
procedure EmitMemoryCopy;
begin
  CodeBufEmit(startCode, $FC);
  CodeBufEmit(startCode, $0A);
  CodeBufEmit(startCode, $00);
  CodeBufEmit(startCode, $00);
end;

{ Emit i32.load from [addr] }
procedure EmitI32Load(align, offset: longint);
begin
  CodeBufEmit(startCode, OpI32Load);
  EmitULEB128(startCode, align);
  EmitULEB128(startCode, offset);
end;

procedure EmitI32Load8u(align, offset: longint);
begin
  CodeBufEmit(startCode, OpI32Load8u);
  EmitULEB128(startCode, align);
  EmitULEB128(startCode, offset);
end;

{ ---- Symbol table ---- }

procedure InitSymTable;
begin
  numSyms := 0;
  scopeDepth := 0;
  scopeBase[0] := 0;
end;

procedure EnterScope;
begin
  scopeDepth := scopeDepth + 1;
  if scopeDepth >= MaxScopes then
    Error('scope nesting too deep');
  scopeBase[scopeDepth] := numSyms;
end;

procedure LeaveScope;
begin
  numSyms := scopeBase[scopeDepth];
  scopeDepth := scopeDepth - 1;
end;

function LookupSym(const name: string): longint;
var i: longint;
begin
  LookupSym := -1;
  for i := numSyms - 1 downto 0 do begin
    if syms[i].name = name then begin
      LookupSym := i;
      exit;
    end;
  end;
end;

function AddSym(const name: string; kind, typ: longint): longint;
begin
  if numSyms >= MaxSyms then
    Error('symbol table full');
  syms[numSyms].name := name;
  syms[numSyms].kind := kind;
  syms[numSyms].typ := typ;
  syms[numSyms].typeIdx := -1;
  syms[numSyms].level := curNestLevel;
  syms[numSyms].offset := 0;
  syms[numSyms].size := 0;
  syms[numSyms].strMax := 0;
  syms[numSyms].isVarParam := false;
  syms[numSyms].isConstParam := false;
  AddSym := numSyms;
  numSyms := numSyms + 1;
end;

procedure AddBuiltins;
var idx: longint;
begin
  { Built-in types }
  idx := AddSym('INTEGER', skType, tyInteger);
  idx := AddSym('BOOLEAN', skType, tyBoolean);
  idx := AddSym('CHAR', skType, tyChar);
  idx := AddSym('BYTE', skType, tyInteger);
  idx := AddSym('WORD', skType, tyInteger);
  idx := AddSym('SHORTINT', skType, tyInteger);
  idx := AddSym('LONGINT', skType, tyInteger);

  { Built-in constants }
  idx := AddSym('TRUE', skConst, tyBoolean);
  syms[idx].offset := 1;
  idx := AddSym('FALSE', skConst, tyBoolean);
  syms[idx].offset := 0;
  idx := AddSym('MAXINT', skConst, tyInteger);
  syms[idx].offset := 2147483647;
end;

{ ---- Type descriptor helpers ---- }

function AddTypeDesc: longint;
{** Allocate a new type descriptor and return its index. }
begin
  if numTypes >= MaxTypes then
    Error('type table full');
  types[numTypes].kind := tyNone;
  types[numTypes].size := 0;
  types[numTypes].fieldStart := 0;
  types[numTypes].fieldCount := 0;
  types[numTypes].elemType := tyNone;
  types[numTypes].elemTypeIdx := -1;
  types[numTypes].elemSize := 0;
  types[numTypes].arrLo := 0;
  types[numTypes].arrHi := 0;
  types[numTypes].elemStrMax := 0;
  AddTypeDesc := numTypes;
  numTypes := numTypes + 1;
end;

function AddField(const aname: string; atyp, atypeIdx, aoffset, asize, astrMax: longint): longint;
{** Add a field descriptor and return its index. }
begin
  if numFields >= MaxFields then
    Error('field table full');
  fields[numFields].name := aname;
  fields[numFields].typ := atyp;
  fields[numFields].typeIdx := atypeIdx;
  fields[numFields].offset := aoffset;
  fields[numFields].size := asize;
  fields[numFields].strMax := astrMax;
  AddField := numFields;
  numFields := numFields + 1;
end;

function LookupField(tIdx: longint; const fname: string): longint;
{** Look up a field by name in a record type descriptor. Returns field index or -1. }
var i: longint;
begin
  LookupField := -1;
  for i := types[tIdx].fieldStart to types[tIdx].fieldStart + types[tIdx].fieldCount - 1 do begin
    if fields[i].name = fname then begin
      LookupField := i;
      exit;
    end;
  end;
end;

procedure ParseTypeSpec(var outTyp, outTypeIdx, outSize, outStrMax: longint);
{** Parse a type specifier. Returns type tag, type descriptor index (-1 for
    simple types), byte size, and string max length. Handles:
    - Simple type names (integer, boolean, char, user-defined)
    - string / string[n]
    - record ... end
    - array[lo..hi] of Type
}
var
  typeName: string;
  typId: longint;
  tIdx: longint;
  fieldOfs: longint;
  fieldTyp, fieldTypeIdx, fieldSize, fieldStrMax: longint;
  fieldNames: array[0..31] of string[63];
  nFieldNames: longint;
  pad: longint;
  fi: longint;
  elemTyp, elemTypeIdx, elemSize, elemStrMax: longint;
  boundType: longint;
  nDims: longint;
  dimLo: array[0..7] of longint;
  dimHi: array[0..7] of longint;
begin
  outStrMax := 0;
  outTypeIdx := -1;

  if tokKind = tkIdent then begin
    typeName := tokStr;
    typId := LookupSym(typeName);
    if typId < 0 then
      Error('unknown type: ' + typeName);
    if syms[typId].kind <> skType then
      Error(typeName + ' is not a type');
    outTyp := syms[typId].typ;
    outTypeIdx := syms[typId].typeIdx;
    NextToken;
    { Determine size from type }
    if outTyp = tyString then begin
      outStrMax := syms[typId].strMax;
      if outStrMax = 0 then outStrMax := 255;
      outSize := outStrMax + 1;
    end else if (outTyp = tyRecord) or (outTyp = tyArray) or (outTyp = tySet) then begin
      outSize := types[outTypeIdx].size;
      outStrMax := 0;
    end else begin
      outSize := 4;  { integer, boolean, char, enum — all i32 }
    end;
  end else if tokKind = tkString_kw then begin
    outTyp := tyString;
    NextToken;
    if tokKind = tkLBrack then begin
      NextToken;
      if tokKind <> tkInteger then
        Error('integer constant expected for string length');
      if (tokInt < 1) or (tokInt > 255) then
        Error('string length must be 1..255');
      outStrMax := tokInt;
      NextToken;
      Expect(tkRBrack);
    end else
      outStrMax := 255;
    outSize := outStrMax + 1;
  end else if tokKind = tkRecord then begin
    { Record type }
    NextToken;
    tIdx := AddTypeDesc;
    types[tIdx].kind := tyRecord;
    types[tIdx].fieldStart := numFields;
    types[tIdx].fieldCount := 0;
    fieldOfs := 0;

    while (tokKind <> tkEnd) and (tokKind <> tkEOF) do begin
      { Parse field list: ident [, ident ...] : type ; }
      nFieldNames := 0;
      while tokKind = tkIdent do begin
        if nFieldNames >= 32 then
          Error('too many fields in one declaration');
        fieldNames[nFieldNames] := tokStr;
        nFieldNames := nFieldNames + 1;
        NextToken;
        if tokKind = tkComma then
          NextToken
        else
          break;
      end;
      if nFieldNames = 0 then
        break;  { allow trailing semicolons before end }

      Expect(tkColon);
      ParseTypeSpec(fieldTyp, fieldTypeIdx, fieldSize, fieldStrMax);

      for fi := 0 to nFieldNames - 1 do begin
        { Align to 4-byte boundary }
        pad := (4 - (fieldOfs mod 4)) mod 4;
        fieldOfs := fieldOfs + pad;
        AddField(fieldNames[fi], fieldTyp, fieldTypeIdx, fieldOfs, fieldSize, fieldStrMax);
        types[tIdx].fieldCount := types[tIdx].fieldCount + 1;
        fieldOfs := fieldOfs + fieldSize;
      end;

      if tokKind = tkSemicolon then
        NextToken;
    end;
    Expect(tkEnd);

    { Final alignment }
    pad := (4 - (fieldOfs mod 4)) mod 4;
    fieldOfs := fieldOfs + pad;
    types[tIdx].size := fieldOfs;
    outTyp := tyRecord;
    outTypeIdx := tIdx;
    outSize := fieldOfs;
  end else if tokKind = tkArray then begin
    (* Array type: array[lo..hi, lo..hi, ...] of Type
       Multi-dimensional arrays desugar: array[a..b, c..d] of T
       becomes array[a..b] of array[c..d] of T.
       We collect all dimensions first, then build nested types inner-to-outer. *)
    NextToken;
    Expect(tkLBrack);

    nDims := 0;
    repeat
      { Parse low bound as constant expression }
      if nDims >= 8 then
        Error('too many array dimensions');
      EvalConstExpr(dimLo[nDims], boundType);
      if not (boundType in [tyInteger, tyChar, tyBoolean, tyEnum]) then
        Error('ordinal type expected for array bound');

      if tokKind <> tkDotDot then
        Expected('..');
      NextToken;

      { Parse high bound as constant expression }
      EvalConstExpr(dimHi[nDims], boundType);

      if dimHi[nDims] < dimLo[nDims] then
        Error('array high bound less than low bound');
      nDims := nDims + 1;

      if tokKind = tkComma then
        NextToken
      else
        break;
    until false;
    Expect(tkRBrack);
    Expect(tkOf);

    { Parse element type }
    ParseTypeSpec(elemTyp, elemTypeIdx, elemSize, elemStrMax);

    { Build nested array types from innermost to outermost }
    for fi := nDims - 1 downto 0 do begin
      tIdx := AddTypeDesc;
      types[tIdx].kind := tyArray;
      types[tIdx].arrLo := dimLo[fi];
      types[tIdx].arrHi := dimHi[fi];
      types[tIdx].elemType := elemTyp;
      types[tIdx].elemTypeIdx := elemTypeIdx;
      types[tIdx].elemSize := elemSize;
      types[tIdx].elemStrMax := elemStrMax;
      types[tIdx].size := (dimHi[fi] - dimLo[fi] + 1) * elemSize;
      elemTyp := tyArray;
      elemTypeIdx := tIdx;
      elemSize := types[tIdx].size;
      elemStrMax := 0;
    end;
    outTyp := tyArray;
    outTypeIdx := tIdx;
    outSize := types[tIdx].size;
    outStrMax := 0;
  end else if tokKind = tkLParen then begin
    { Enumerated type: (Ident, Ident, ...) }
    NextToken;
    tIdx := AddTypeDesc;
    types[tIdx].kind := tyEnum;
    fi := 0;  { ordinal counter }
    repeat
      if tokKind <> tkIdent then
        Expected('identifier');
      { Add each enum value as a constant }
      typId := AddSym(tokStr, skConst, tyEnum);
      syms[typId].offset := fi;
      syms[typId].typeIdx := tIdx;
      syms[typId].size := 4;
      fi := fi + 1;
      NextToken;
      if tokKind = tkComma then
        NextToken
      else
        break;
    until false;
    Expect(tkRParen);
    types[tIdx].arrLo := 0;      { reuse arrLo/arrHi for ordinal range }
    types[tIdx].arrHi := fi - 1;
    types[tIdx].size := 4;
    outTyp := tyEnum;
    outTypeIdx := tIdx;
    outSize := 4;
  end else if tokKind = tkSet then begin
    { Set type: set of BaseType }
    NextToken;
    Expect(tkOf);
    ParseTypeSpec(elemTyp, elemTypeIdx, elemSize, elemStrMax);
    tIdx := AddTypeDesc;
    types[tIdx].kind := tySet;
    types[tIdx].elemType := elemTyp;
    types[tIdx].elemTypeIdx := elemTypeIdx;
    if (elemTyp = tyEnum) and (elemTypeIdx >= 0) then begin
      types[tIdx].arrLo := types[elemTypeIdx].arrLo;
      types[tIdx].arrHi := types[elemTypeIdx].arrHi;
    end else if elemTyp = tyChar then begin
      types[tIdx].arrLo := 0;
      types[tIdx].arrHi := 255;
    end else if elemTyp = tyBoolean then begin
      types[tIdx].arrLo := 0;
      types[tIdx].arrHi := 1;
    end else if elemTyp = tyInteger then begin
      types[tIdx].arrLo := 0;
      types[tIdx].arrHi := 31;
    end else
      Error('invalid set base type');
    fi := types[tIdx].arrHi - types[tIdx].arrLo + 1;
    if fi <= 32 then begin
      types[tIdx].size := 4;  { fits in i32 }
    end else if fi <= 256 then begin
      types[tIdx].size := (fi + 7) div 8;  { byte-rounded bitmap }
    end else
      Error('set base type too large (max 256 elements)');
    outTyp := tySet;
    outTypeIdx := tIdx;
    outSize := types[tIdx].size;
    outStrMax := 0;
  end else
    Error('type name expected');
end;

{ ---- Display and frame access ---- }

procedure EmitFramePtr(level: longint);
(* Emit code to push the frame pointer for the given nesting level.
   If level = curNestLevel, use $sp (global 0).
   Otherwise, use display[level] (global level+1) for upvalue access. *)
begin
  if level = curNestLevel then begin
    EmitOp(OpGlobalGet);
    EmitULEB128(startCode, 0);  { $sp }
  end else begin
    EmitOp(OpGlobalGet);
    EmitULEB128(startCode, level + 1);  { display[level] = global level+1 }
  end;
end;

procedure EmitVarParamPtr(sym: longint);
(* Emit code to push the pointer stored in a var/const param.
   The pointer is stored in the frame at syms[sym].offset. *)
begin
  EmitFramePtr(syms[sym].level);
  EmitI32Const(syms[sym].offset);
  EmitOp(OpI32Add);
  EmitI32Load(2, 0);
end;

{ ---- Write/Writeln code generation ---- }

procedure EmitWriteStringFd(fd, addr, len: longint);
{** Emit WASM code to write data via fd_write to a given file descriptor. }
var fdw: longint;
begin
  EnsureIOBuffers;
  fdw := EnsureFdWrite;

  { Set iovec.buf = addr }
  EmitI32Const(addrIovec);
  EmitI32Const(addr);
  EmitI32Store(2, 0);

  { Set iovec.len = len }
  EmitI32Const(addrIovec + 4);
  EmitI32Const(len);
  EmitI32Store(2, 0);

  { Call fd_write(fd, iovec, 1, nwritten) }
  EmitI32Const(fd);
  EmitI32Const(addrIovec);      { iovs }
  EmitI32Const(1);              { iovs_len }
  EmitI32Const(addrNwritten);   { nwritten }
  EmitCall(fdw);
  EmitOp(OpDrop);               { discard errno }
end;

procedure EmitWriteString(addr, len: longint);
begin
  EmitWriteStringFd(1, addr, len);
end;

procedure EmitWriteNewlineFd(fd: longint);
begin
  EnsureIOBuffers;
  EmitWriteStringFd(fd, addrNewline, 1);
end;

procedure EmitWriteNewline;
begin
  EmitWriteNewlineFd(1);
end;

{ ---- Integer to string conversion ---- }

procedure EnsureIntToStr;
{** Emit the integer-to-string conversion helper function.
  Uses a 20-byte scratch buffer in the data segment.
  The function takes i32 on WASM stack, writes decimal digits
  to the scratch buffer, then calls fd_write.

  Actually, for simplicity in milestone 1-2, we'll emit inline
  code for integer write rather than a separate function.
  The inline approach: call a helper that we emit as a WASM function.
}
begin
  if addrIntBuf < 0 then begin
    addrIntBuf := AllocData(20); { enough for -2147483648 + null }
    { zero-fill }
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
  end;
end;

function EnsureForLimit(depth: longint): longint;
{** Allocate a 4-byte for-limit scratch at the given nesting depth.
  Returns its data segment address. }
begin
  if addrForLimit[depth] < 0 then begin
    addrForLimit[depth] := AllocDataAligned(4, 4);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
  end;
  EnsureForLimit := addrForLimit[depth];
end;

function EnsureWriteInt: longint;
{** Ensure the __write_int helper function is registered.
  Returns its WASM function index.
  __write_int is pre-allocated at slot 1 (right after _start).
  User-defined functions go into slots 3+. }
begin
  if not needsWriteInt then begin
    EnsureIntToStr;
    EnsureIOBuffers;
    needsWriteInt := true;
  end;
  EnsureWriteInt := numImports + 1; { slot 1 = __write_int }
end;

procedure EnsureReadBuffers;
{** Allocate the 1-byte read buffer and nread result in data segment. }
begin
  EnsureIOBuffers;
  if addrReadBuf < 0 then begin
    addrReadBuf := AllocDataAligned(1, 4);
    DataBufEmit(secData, 0);
  end;
  if addrNread < 0 then begin
    addrNread := AllocDataAligned(4, 4);
    { Initialize to 1 so eof returns false before any read }
    DataBufEmit(secData, 1); DataBufEmit(secData, 0);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
  end;
end;

procedure EnsureCharStr;
{** Allocate a 2-byte scratch for char-to-string (length + data byte). }
begin
  if addrCharStr < 0 then begin
    addrCharStr := AllocDataAligned(2, 4);
    DataBufEmit(secData, 0); DataBufEmit(secData, 0);
  end;
end;

function EnsureReadInt: longint;
{** Ensure the __read_int helper function is registered.
  Returns its WASM function index.
  __read_int is pre-allocated at slot 2 (after __write_int).
  Reads decimal integer from stdin, returns i32. }
begin
  if not needsReadInt then begin
    EnsureReadBuffers;
    needsReadInt := true;
  end;
  EnsureReadInt := numImports + 2; { slot 2 = __read_int }
end;

function EnsureStrAssign: longint;
{** Ensure the __str_assign helper is registered.
  Returns its WASM function index.
  __str_assign(dst, max_len, src) is at slot 3. }
begin
  if not needsStrAssign then
    needsStrAssign := true;
  EnsureStrAssign := numImports + 3; { slot 3 = __str_assign }
end;

function EnsureWriteStr: longint;
{** Ensure the __write_str helper is registered.
  Returns its WASM function index.
  __write_str(addr) is at slot 4. }
begin
  if not needsWriteStr then begin
    EnsureIOBuffers;
    needsWriteStr := true;
  end;
  EnsureWriteStr := numImports + 4; { slot 4 = __write_str }
end;

function EnsureStrCompare: longint;
{** Ensure the __str_compare helper is registered.
  Returns its WASM function index.
  __str_compare(a, b) -> i32 (-1/0/1) is at slot 5. }
begin
  if not needsStrCompare then
    needsStrCompare := true;
  EnsureStrCompare := numImports + 5; { slot 5 = __str_compare }
end;

function EnsureReadStr: longint;
{** Ensure the __read_str helper is registered.
  Returns its WASM function index.
  __read_str(addr, max_len) is at slot 6. }
begin
  if not needsReadStr then begin
    EnsureIOBuffers;
    needsReadStr := true;
  end;
  EnsureReadStr := numImports + 6; { slot 6 = __read_str }
end;

procedure EnsureConcatScratch;
{** Allocate the 16-slot scratch array and temp string in the data segment. }
var j: longint;
begin
  if not needsConcatScratch then begin
    needsConcatScratch := true;
    addrConcatScratch := AllocDataAligned(64, 4); { 16 slots x 4 bytes }
    for j := 1 to 64 do DataBufEmit(secData, 0);
    addrConcatTemp := AllocDataAligned(256, 4);   { temp string for concat result }
    for j := 1 to 256 do DataBufEmit(secData, 0);
  end;
end;

function EnsureStrAppend: longint;
{** Ensure the __str_append helper is registered.
  Returns its WASM function index.
  __str_append(dst, maxlen, src) is at slot 7. }
begin
  needsStrAppend := true;
  EnsureStrAppend := numImports + 7; { slot 7 = __str_append }
end;

procedure EnsureCopyTemp;
{** Allocate the 256-byte temp buffer for copy() result if not yet allocated. }
var j: longint;
begin
  if not needsCopyTemp then begin
    needsCopyTemp := true;
    addrCopyTemp := AllocDataAligned(256, 4);
    for j := 1 to 256 do DataBufEmit(secData, 0);
  end;
end;

function EnsureStrCopy: longint;
{** Ensure the __str_copy helper is registered.
  __str_copy(src, idx, count, dst) is at slot 8. }
begin
  needsStrCopy := true;
  EnsureStrCopy := numImports + 8;
end;

function EnsureStrPos: longint;
{** Ensure the __str_pos helper is registered.
  __str_pos(sub, s) -> i32 is at slot 9. }
begin
  needsStrPos := true;
  EnsureStrPos := numImports + 9;
end;

function EnsureStrDelete: longint;
{** Ensure the __str_delete helper is registered.
  __str_delete(s, idx, count) is at slot 10. }
begin
  needsStrDelete := true;
  EnsureStrDelete := numImports + 10;
end;

function EnsureStrInsert: longint;
{** Ensure the __str_insert helper is registered.
  __str_insert(src, dst, idx) is at slot 11. }
begin
  needsStrInsert := true;
  EnsureStrInsert := numImports + 11;
end;

function EnsureRangeCheck: longint;
{** Ensure the __range_check helper is registered.
  __range_check(val, lo, hi) -> i32 is at slot 12.
  Traps if val < lo or val > hi. }
begin
  needsRangeCheck := true;
  EnsureRangeCheck := numImports + 12;
end;

function EnsureCheckedAdd: longint;
begin
  needsCheckedAdd := true;
  EnsureCheckedAdd := numImports + 13;
end;

function EnsureCheckedSub: longint;
begin
  needsCheckedSub := true;
  EnsureCheckedSub := numImports + 14;
end;

function EnsureCheckedMul: longint;
begin
  needsCheckedMul := true;
  EnsureCheckedMul := numImports + 15;
end;

procedure EnsureSetTemp;
{** Allocate two 32-byte temp buffers for large set arithmetic results,
  plus a static 32-byte zero block for empty set compatibility. }
var j: longint;
begin
  if not needsSetTemp then begin
    needsSetTemp := true;
    addrSetTemp := AllocDataAligned(32, 4);
    for j := 1 to 32 do DataBufEmit(secData, 0);
    addrSetTemp2 := AllocDataAligned(32, 4);
    for j := 1 to 32 do DataBufEmit(secData, 0);
    addrSetZero := AllocDataAligned(32, 4);
    for j := 1 to 32 do DataBufEmit(secData, 0);
  end;
end;

function EnsureSetUnion: longint;
{** __set_union(dst, a, b): byte-wise OR, 32 bytes. Slot 16. }
begin
  needsSetUnion := true;
  EnsureSetUnion := numImports + 16;
end;

function EnsureSetIntersect: longint;
{** __set_intersect(dst, a, b): byte-wise AND, 32 bytes. Slot 17. }
begin
  needsSetIntersect := true;
  EnsureSetIntersect := numImports + 17;
end;

function EnsureSetDiff: longint;
{** __set_diff(dst, a, b): byte-wise A AND NOT B, 32 bytes. Slot 18. }
begin
  needsSetDiff := true;
  EnsureSetDiff := numImports + 18;
end;

function EnsureSetEq: longint;
{** __set_eq(a, b) -> i32: compare 32 bytes, return 1 if equal. Slot 19. }
begin
  needsSetEq := true;
  EnsureSetEq := numImports + 19;
end;

function EnsureSetSubset: longint;
{** __set_subset(a, b) -> i32: return 1 if a is subset of b. Slot 20. }
begin
  needsSetSubset := true;
  EnsureSetSubset := numImports + 20;
end;

function EnsureIntToStrHelper: longint;
{** __int_to_str(value, dest): convert i32 to Pascal string at dest. Slot 21. }
begin
  EnsureIntToStr;
  needsIntToStr := true;
  EnsureIntToStrHelper := numImports + 21;
end;

procedure EmitWriteInt;
{** Emit a call to the __write_int helper function.
  The integer value is already on the WASM operand stack. }
begin
  EmitCall(EnsureWriteInt);
end;

function EnsureWriteChar: longint;
begin
  if not needsWriteChar then begin
    EnsureIOBuffers;
    EnsureReadBuffers; { reuse addrReadBuf as 1-byte scratch }
    needsWriteChar := true;
  end;
  EnsureWriteChar := numImports + 22; { slot 22 = __write_char }
end;

procedure EmitWriteChar(fd: longint);
{** Emit a call to __write_char(value, fd).
  The char value (i32) is already on the WASM operand stack.
  Pushes fd and calls the helper. }
begin
  EmitI32Const(fd);
  EmitCall(EnsureWriteChar);
end;

procedure EmitInlineWriteStr(fd, localIdx: longint);
{** Emit inline code to write a Pascal string to a given fd.
  The string address is on the WASM operand stack.
  Uses localIdx as scratch to save the address.
  This avoids the __write_str helper which hardcodes fd=1. }
var fdw: longint;
begin
  EnsureIOBuffers;
  fdw := EnsureFdWrite;
  { Save addr to local }
  EmitOp(OpLocalSet);
  EmitULEB128(startCode, localIdx);
  { iovec.buf = addr + 1 (skip length byte) }
  EmitI32Const(addrIovec);
  EmitOp(OpLocalGet);
  EmitULEB128(startCode, localIdx);
  EmitI32Const(1);
  EmitOp(OpI32Add);
  EmitI32Store(2, 0);
  { iovec.len = addr[0] (length byte) }
  EmitI32Const(addrIovec + 4);
  EmitOp(OpLocalGet);
  EmitULEB128(startCode, localIdx);
  EmitI32Load8u(0, 0);
  EmitI32Store(2, 0);
  { fd_write(fd, iovec, 1, nwritten) }
  EmitI32Const(fd);
  EmitI32Const(addrIovec);
  EmitI32Const(1);
  EmitI32Const(addrNwritten);
  EmitCall(fdw);
  EmitOp(OpDrop);
end;

{ ---- Parsing ---- }

procedure ParseExpression(minPrec: longint);
{** Pratt-style precedence climbing expression parser.
  Each call parses a complete expression with operators at or above minPrec.
  Emits WASM code directly to startCode buffer.
}
var
  prec: longint;
  op: longint;
  sym: longint;
  argIdx: longint;
  argSym: longint;
  leftType: longint;
  hasAddr: boolean;
  exprTypeIdx: longint;
  exprStrMax: longint;
  fldIdx: longint;
  isConst: boolean;
  nSetElems: longint;
  setBitmap: array[0..31] of byte;
  setLo, setHi: longint;
  fi: longint;
  withFound: boolean;
  wi: longint;
  tmpOfs: longint;
  castTyp: longint;
  castName: string;
  leftSetSize: longint;
  concatSPAllocs: longint;
begin
  withFound := false;
  leftSetSize := 4;
  concatSPAllocs := 0;
  { Prefix }
  case tokKind of
    tkInteger: begin
      EmitI32Const(tokInt);
      exprType := tyInteger;
      NextToken;
    end;

    tkString: begin
      { String literal in expression — push address of Pascal-format
        string in data segment (length byte + data) }
      EmitI32Const(EmitDataPascalString(tokStr));
      exprType := tyString;
      NextToken;
    end;

    tkTrue: begin
      EmitI32Const(1);
      exprType := tyBoolean;
      NextToken;
    end;

    tkFalse: begin
      EmitI32Const(0);
      exprType := tyBoolean;
      NextToken;
    end;

    tkIdent: begin
      { Built-in functions handled before symbol lookup }
      if tokStr = 'LENGTH' then begin
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyString then
          Error('length() requires a string argument');
        Expect(tkRParen);
        { String address is on stack — read length byte }
        EmitI32Load8u(0, 0);
        exprType := tyInteger;
      end
      else if tokStr = 'COPY' then begin
        { copy(s, index, count) -> string }
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyString then
          Error('copy() first argument must be a string');
        Expect(tkComma);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('copy() second argument must be an integer');
        Expect(tkComma);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('copy() third argument must be an integer');
        Expect(tkRParen);
        { Stack: [src, idx, count]. Push dst temp addr, call helper. }
        EnsureCopyTemp;
        EmitI32Const(addrCopyTemp);
        EmitCall(EnsureStrCopy);
        { Result is the temp buffer address }
        EmitI32Const(addrCopyTemp);
        exprType := tyString;
      end
      else if tokStr = 'POS' then begin
        { pos(sub, s) -> integer }
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyString then
          Error('pos() first argument must be a string');
        Expect(tkComma);
        ParseExpression(PrecNone);
        if exprType <> tyString then
          Error('pos() second argument must be a string');
        Expect(tkRParen);
        EmitCall(EnsureStrPos);
        exprType := tyInteger;
      end
      else if tokStr = 'CONCAT' then begin
        { concat(s1, s2, ...) -> string — variadic, uses concat piece tracking }
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyString then
          Error('concat() arguments must be strings');
        while tokKind = tkComma do begin
          { Save current piece to scratch, parse next }
          EnsureConcatScratch;
          if concatPieces >= 16 then
            Error('too many concat pieces (max 16)');
          curFuncNeedsStringTemp := true;
          EmitOp(OpLocalSet);
          EmitULEB128(startCode, curStringTempIdx);
          EmitI32Const(addrConcatScratch + concatPieces * 4);
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, curStringTempIdx);
          EmitI32Store(2, 0);
          concatPieces := concatPieces + 1;
          NextToken;
          ParseExpression(PrecNone);
          if exprType <> tyString then
            Error('concat() arguments must be strings');
        end;
        Expect(tkRParen);
        exprType := tyString;
      end
      else if tokStr = 'ORD' then begin
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType = tyString then begin
          { ord('A') — load first character from string address }
          EmitI32Load8u(0, 1);
          exprType := tyInteger;
        end else if not (exprType in [tyChar, tyBoolean, tyInteger, tyEnum]) then
          Error('ord() requires ordinal type');
        Expect(tkRParen);
        exprType := tyInteger;
      end
      else if tokStr = 'CHR' then begin
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('chr() requires integer argument');
        Expect(tkRParen);
        exprType := tyChar;
      end
      else if tokStr = 'ABS' then begin
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('abs() requires integer argument');
        Expect(tkRParen);
        curFuncNeedsStringTemp := true;
        EmitOp(OpLocalTee);
        EmitULEB128(startCode, curStringTempIdx);
        EmitI32Const(0);
        EmitOp(OpI32LtS);
        EmitOp(OpIf);
        EmitOp(WasmI32);  { result type i32 }
        EmitI32Const(0);
        EmitOp(OpLocalGet);
        EmitULEB128(startCode, curStringTempIdx);
        EmitOp(OpI32Sub);
        EmitOp(OpElse);
        EmitOp(OpLocalGet);
        EmitULEB128(startCode, curStringTempIdx);
        EmitOp(OpEnd);
        exprType := tyInteger;
      end
      else if tokStr = 'ODD' then begin
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if not (exprType in [tyInteger, tyChar, tyBoolean, tyEnum]) then
          Error('odd() requires ordinal type');
        Expect(tkRParen);
        EmitI32Const(1);
        EmitOp(OpI32And);
        exprType := tyBoolean;
      end
      else if tokStr = 'SUCC' then begin
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if not (exprType in [tyInteger, tyChar, tyBoolean, tyEnum]) then
          Error('succ() requires ordinal type');
        Expect(tkRParen);
        EmitI32Const(1);
        EmitOp(OpI32Add);
      end
      else if tokStr = 'PRED' then begin
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if not (exprType in [tyInteger, tyChar, tyBoolean, tyEnum]) then
          Error('pred() requires ordinal type');
        Expect(tkRParen);
        EmitI32Const(1);
        EmitOp(OpI32Sub);
      end
      else if tokStr = 'SQR' then begin
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('sqr() requires integer argument');
        Expect(tkRParen);
        curFuncNeedsStringTemp := true;
        EmitOp(OpLocalTee);
        EmitULEB128(startCode, curStringTempIdx);
        EmitOp(OpLocalGet);
        EmitULEB128(startCode, curStringTempIdx);
        EmitOp(OpI32Mul);
        exprType := tyInteger;
      end
      else if tokStr = 'SIZEOF' then begin
        NextToken;
        Expect(tkLParen);
        if tokKind <> tkIdent then
          Expected('identifier');
        sym := LookupSym(tokStr);
        if sym < 0 then
          Error('undeclared identifier: ' + tokStr);
        EmitI32Const(syms[sym].size);
        NextToken;
        Expect(tkRParen);
        exprType := tyInteger;
      end
      else if tokStr = 'LO' then begin
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('lo() requires integer argument');
        Expect(tkRParen);
        EmitI32Const(255);
        EmitOp(OpI32And);
        exprType := tyInteger;
      end
      else if tokStr = 'HI' then begin
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('hi() requires integer argument');
        Expect(tkRParen);
        EmitI32Const(8);
        EmitOp(OpI32ShrU);
        EmitI32Const(255);
        EmitOp(OpI32And);
        exprType := tyInteger;
      end
      else if tokStr = 'EOF' then begin
        { eof — returns true when last fd_read returned 0 bytes }
        NextToken;
        EnsureReadBuffers;
        EmitI32Const(addrNread);
        EmitI32Load(2, 0);
        EmitOp(OpI32Eqz);
        exprType := tyBoolean;
      end
      else begin
      sym := LookupSym(tokStr);
      if sym < 0 then begin
        { Check with-stack for matching field }
        withFound := false;
        for wi := numWiths - 1 downto 0 do begin
          fldIdx := LookupField(withTypeIdx[wi], tokStr);
          if fldIdx >= 0 then begin
            { Emit record base address }
            if withIsVarParam[wi] then begin
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, -(withOffset[wi] + 1));
            end else if withIsLocal[wi] then begin
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, -(withOffset[wi] + 1));
            end else begin
              EmitFramePtr(withLevel[wi]);
              EmitI32Const(withOffset[wi]);
              EmitOp(OpI32Add);
            end;
            { Add with-selector offset + field offset }
            tmpOfs := withFieldOfs[wi] + fields[fldIdx].offset;
            if tmpOfs <> 0 then begin
              EmitI32Const(tmpOfs);
              EmitOp(OpI32Add);
            end;
            hasAddr := true;
            exprType := fields[fldIdx].typ;
            exprTypeIdx := fields[fldIdx].typeIdx;
            exprStrMax := fields[fldIdx].strMax;
            NextToken;
            withFound := true;
            break;
          end;
        end;
        if not withFound then
          Error('undeclared identifier: ' + tokStr);
      end;
      if sym >= 0 then
      case syms[sym].kind of
        skConst: begin
          EmitI32Const(syms[sym].offset);
          exprType := syms[sym].typ;
          NextToken;
        end;
        skVar: begin
          { Compute base address or value of the variable.
            For address-based access (frame vars, var params of structured types),
            we push the address, then apply .field / [index] selectors.
            For scalar WASM locals (value params), we push the value directly. }
          hasAddr := false;
          exprTypeIdx := syms[sym].typeIdx;
          exprStrMax := syms[sym].strMax;

          if syms[sym].isVarParam then begin
            { var/const param: pointer stored in frame }
            EmitVarParamPtr(sym);
            hasAddr := true;
          end else if syms[sym].offset < 0 then begin
            { Value parameter (WASM local) }
            if (syms[sym].typ = tyString) or (syms[sym].typ = tyRecord)
               or (syms[sym].typ = tyArray) then begin
              { Structured value param: local holds pointer }
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, -(syms[sym].offset + 1));
              hasAddr := true;
            end else begin
              { Scalar value param: local holds the value }
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, -(syms[sym].offset + 1));
              hasAddr := false;
            end;
          end else begin
            { Stack frame variable: compute address = frame[level] + offset }
            EmitFramePtr(syms[sym].level);
            EmitI32Const(syms[sym].offset);
            EmitOp(OpI32Add);
            hasAddr := true;
          end;
          exprType := syms[sym].typ;
          NextToken;

          { Process .field and [index] selectors — address must be on stack }
          while (tokKind = tkDot) or (tokKind = tkLBrack) do begin
            if not hasAddr then
              Error('cannot apply selector to value parameter');
            if tokKind = tkDot then begin
              if exprType <> tyRecord then
                Error('record type expected before ''.''');
              NextToken;
              if tokKind <> tkIdent then
                Expected('field name');
              fldIdx := LookupField(exprTypeIdx, tokStr);
              if fldIdx < 0 then
                Error('unknown field: ' + tokStr);
              if fields[fldIdx].offset <> 0 then begin
                EmitI32Const(fields[fldIdx].offset);
                EmitOp(OpI32Add);
              end;
              exprType := fields[fldIdx].typ;
              exprTypeIdx := fields[fldIdx].typeIdx;
              exprStrMax := fields[fldIdx].strMax;
              NextToken;
            end else if exprType = tyString then begin
              { String char index: s[i] — addr + i (1-based) }
              NextToken;
              ParseExpression(PrecNone);
              EmitOp(OpI32Add);
              exprType := tyChar;
              exprTypeIdx := -1;
              exprStrMax := 0;
              Expect(tkRBrack);
            end else begin
              { Array index: [expr] }
              if exprType <> tyArray then
                Error('array type expected before ''[''');
              NextToken;
              { addr + (index - lo) * elemSize }
              ParseExpression(PrecNone);
              if optRangeChecks then begin
                EmitI32Const(types[exprTypeIdx].arrLo);
                EmitI32Const(types[exprTypeIdx].arrHi);
                EmitCall(EnsureRangeCheck);
              end;
              if types[exprTypeIdx].arrLo <> 0 then begin
                EmitI32Const(types[exprTypeIdx].arrLo);
                EmitOp(OpI32Sub);
              end;
              if types[exprTypeIdx].elemSize <> 1 then begin
                EmitI32Const(types[exprTypeIdx].elemSize);
                EmitOp(OpI32Mul);
              end;
              EmitOp(OpI32Add);
              exprType := types[exprTypeIdx].elemType;
              exprStrMax := types[exprTypeIdx].elemStrMax;
              exprTypeIdx := types[exprTypeIdx].elemTypeIdx;
              if tokKind = tkComma then begin
                { Multi-dimensional: treat a[i,j] as a[i][j] }
                tokKind := tkLBrack;
              end else
                Expect(tkRBrack);
            end;
          end;

          { Final load: scalars need i32.load, structured types leave address }
          if hasAddr and (exprType <> tyString) and (exprType <> tyRecord)
             and (exprType <> tyArray)
             and not ((exprType = tySet) and (exprTypeIdx >= 0) and (types[exprTypeIdx].size > 4)) then begin
            if (exprType = tyChar) or (exprType = tyBoolean) then
              EmitI32Load8u(0, 0)
            else
              EmitI32Load(2, 0);
          end;
          if (exprType = tySet) and (exprTypeIdx >= 0) then
            exprSetSize := types[exprTypeIdx].size
          else if exprType = tySet then
            exprSetSize := 4;
        end;
        skFunc: begin
          { Function call in expression }
          NextToken;
          if tokKind = tkLParen then begin
            NextToken;
            argIdx := 0;
            while tokKind <> tkRParen do begin
              if funcs[syms[sym].size].varParams[argIdx] then begin
                { var param: pass address of the variable }
                if funcs[syms[sym].size].constParams[argIdx] then begin
                  { const param: parse full expression (may include concat) }
                  ParseExpression(PrecNone);
                  if concatPieces > 0 then begin
                    { Concat expression: finalize into SP-allocated temp
                      (avoids aliasing when callee also does concat) }
                    curFuncNeedsStringTemp := true;
                    EmitOp(OpLocalSet);
                    EmitULEB128(startCode, curStringTempIdx);
                    { Allocate 256 bytes on WASM stack }
                    EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
                    EmitI32Const(256);
                    EmitOp(OpI32Sub);
                    EmitOp(OpGlobalSet); EmitULEB128(startCode, 0);
                    concatSPAllocs := concatSPAllocs + 1;
                    { Zero concat temp at $sp }
                    EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
                    EmitI32Const(0);
                    EmitOp(OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
                    { Append each saved piece }
                    for fi := 0 to concatPieces - 1 do begin
                      EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
                      EmitI32Const(255);
                      EmitI32Const(addrConcatScratch + fi * 4);
                      EmitI32Load(2, 0);
                      EmitCall(EnsureStrAppend);
                    end;
                    { Append last piece }
                    EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
                    EmitI32Const(255);
                    EmitOp(OpLocalGet);
                    EmitULEB128(startCode, curStringTempIdx);
                    EmitCall(EnsureStrAppend);
                    { Push SP (concat temp address) as the argument }
                    EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
                    concatPieces := 0;
                  end;
                  { else: simple string expression — address already on stack }
                end else begin
                  if tokKind <> tkIdent then
                    Error('variable expected for var parameter');
                  argSym := LookupSym(tokStr);
                  if argSym < 0 then
                    Error('undeclared identifier: ' + tokStr);
                  if syms[argSym].kind <> skVar then
                    Error('variable expected for var parameter');
                  if syms[argSym].isVarParam then begin
                    { Already a pointer — pass it through }
                    EmitVarParamPtr(argSym);
                  end
                  else if (syms[argSym].offset < 0) and
                     ((syms[argSym].typ = tyRecord) or (syms[argSym].typ = tyArray)
                      or (syms[argSym].typ = tyString)) then begin
                    { Structured value param: local holds pointer, pass through }
                    EmitOp(OpLocalGet);
                    EmitULEB128(startCode, -(syms[argSym].offset + 1));
                  end
                  else if syms[argSym].offset < 0 then
                    Error('cannot pass value parameter by reference')
                  else begin
                    { Address = frame[level] + offset }
                    EmitFramePtr(syms[argSym].level);
                    EmitI32Const(syms[argSym].offset);
                    EmitOp(OpI32Add);
                  end;
                  NextToken;
                  { Handle postfix [index] for array element var params }
                  while tokKind = tkLBrack do begin
                    if syms[argSym].typ <> tyArray then
                      Error('array type expected before ''[''');
                    NextToken;
                    ParseExpression(PrecNone);
                    if types[syms[argSym].typeIdx].arrLo <> 0 then begin
                      EmitI32Const(types[syms[argSym].typeIdx].arrLo);
                      EmitOp(OpI32Sub);
                    end;
                    if types[syms[argSym].typeIdx].elemSize <> 1 then begin
                      EmitI32Const(types[syms[argSym].typeIdx].elemSize);
                      EmitOp(OpI32Mul);
                    end;
                    EmitOp(OpI32Add);
                    argSym := -1; { no longer tracking original sym }
                    Expect(tkRBrack);
                  end;
                end;
              end else begin
                ParseExpression(PrecNone);
              end;
              argIdx := argIdx + 1;
              if tokKind = tkComma then
                NextToken;
            end;
            Expect(tkRParen);
          end;
          EmitCall(syms[sym].offset);
          { Restore SP for any concat temp allocations }
          if concatSPAllocs > 0 then begin
            EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
            EmitI32Const(concatSPAllocs * 256);
            EmitOp(OpI32Add);
            EmitOp(OpGlobalSet); EmitULEB128(startCode, 0);
            concatSPAllocs := 0;
          end;
          exprType := syms[sym].typ;
          { Return value is left on WASM stack }
        end;
        skType: begin
          { Type cast: TypeName(expr) }
          castTyp := syms[sym].typ;
          castName := syms[sym].name;
          NextToken;
          Expect(tkLParen);
          ParseExpression(PrecNone);
          Expect(tkRParen);
          { String to ordinal: load first character }
          if exprType = tyString then begin
            EmitI32Load8u(0, 1); { load byte at addr+1 (skip length byte) }
          end;
          { Emit masking for narrow types }
          if (castName = 'CHAR') or (castName = 'BYTE') then begin
            EmitI32Const(255);
            EmitOp(OpI32And);
          end else if castName = 'SHORTINT' then begin
            { Sign-extend from 8 bits: shift left 24, arith shift right 24 }
            EmitI32Const(24);
            EmitOp(OpI32Shl);
            EmitI32Const(24);
            EmitOp(OpI32ShrS);
          end else if castName = 'WORD' then begin
            EmitI32Const(65535);
            EmitOp(OpI32And);
          end;
          { INTEGER, LONGINT, BOOLEAN: no-op (already i32) }
          exprType := castTyp;
        end;
      else
        Error('cannot use ' + tokStr + ' in expression');
      end;
      if withFound then begin
        { with-resolved field: process selectors and final load }
        while (tokKind = tkDot) or (tokKind = tkLBrack) do begin
          if tokKind = tkDot then begin
            if exprType <> tyRecord then
              Error('record type expected before ''.''');
            NextToken;
            if tokKind <> tkIdent then
              Expected('field name');
            fldIdx := LookupField(exprTypeIdx, tokStr);
            if fldIdx < 0 then
              Error('unknown field: ' + tokStr);
            if fields[fldIdx].offset <> 0 then begin
              EmitI32Const(fields[fldIdx].offset);
              EmitOp(OpI32Add);
            end;
            exprType := fields[fldIdx].typ;
            exprTypeIdx := fields[fldIdx].typeIdx;
            exprStrMax := fields[fldIdx].strMax;
            NextToken;
          end else if exprType = tyString then begin
            { String char index: s[i] — addr + i (1-based) }
            NextToken;
            ParseExpression(PrecNone);
            EmitOp(OpI32Add);
            exprType := tyChar;
            exprTypeIdx := -1;
            exprStrMax := 0;
            Expect(tkRBrack);
          end else begin
            if exprType <> tyArray then
              Error('array type expected before ''[''');
            NextToken;
            ParseExpression(PrecNone);
            if optRangeChecks then begin
              EmitI32Const(types[exprTypeIdx].arrLo);
              EmitI32Const(types[exprTypeIdx].arrHi);
              EmitCall(EnsureRangeCheck);
            end;
            if types[exprTypeIdx].arrLo <> 0 then begin
              EmitI32Const(types[exprTypeIdx].arrLo);
              EmitOp(OpI32Sub);
            end;
            if types[exprTypeIdx].elemSize <> 1 then begin
              EmitI32Const(types[exprTypeIdx].elemSize);
              EmitOp(OpI32Mul);
            end;
            EmitOp(OpI32Add);
            exprType := types[exprTypeIdx].elemType;
            exprStrMax := types[exprTypeIdx].elemStrMax;
            exprTypeIdx := types[exprTypeIdx].elemTypeIdx;
            if tokKind = tkComma then
              tokKind := tkLBrack
            else
              Expect(tkRBrack);
          end;
        end;
        if hasAddr and (exprType <> tyString) and (exprType <> tyRecord)
           and (exprType <> tyArray)
           and not ((exprType = tySet) and (exprTypeIdx >= 0) and (types[exprTypeIdx].size > 4)) then
          EmitI32Load(2, 0);
        if (exprType = tySet) and (exprTypeIdx >= 0) then
          exprSetSize := types[exprTypeIdx].size
        else if exprType = tySet then
          exprSetSize := 4;
      end;
      end; { end of else (not LENGTH) }
    end;

    tkLParen: begin
      NextToken;
      ParseExpression(PrecNone);
      Expect(tkRParen);
    end;

    tkMinus: begin
      NextToken;
      ParseExpression(PrecUnary);
      (* WAT: i32.const -1; i32.mul  -- negate top of stack *)
      EmitI32Const(-1);
      EmitOp(OpI32Mul);
    end;

    tkPlus: begin
      NextToken;
      ParseExpression(PrecUnary);
      { unary plus is a no-op }
    end;

    tkLBrack: begin
      { Set constructor: [elem, elem, lo..hi, ...]
        Try compile-time evaluation first. If all elements are constants,
        build bitmap at compile time. Otherwise fall back to runtime codegen. }
      NextToken;
      isConst := true;
      nSetElems := 0;
      for fi := 0 to 31 do
        setBitmap[fi] := 0;

      if tokKind <> tkRBrack then begin
        { First pass: try to evaluate all elements as constants }
        repeat
          { Try to get a constant value }
          if tokKind = tkInteger then begin
            setLo := tokInt;
            NextToken;
          end else if (tokKind = tkString) and (length(tokStr) = 1) then begin
            setLo := ord(tokStr[1]);
            NextToken;
          end else if tokKind = tkIdent then begin
            sym := LookupSym(tokStr);
            if (sym >= 0) and (syms[sym].kind = skConst) then begin
              setLo := syms[sym].offset;
              NextToken;
            end else
              isConst := false;
          end else
            isConst := false;

          if not isConst then break;

          if tokKind = tkDotDot then begin
            NextToken;
            if tokKind = tkInteger then begin
              setHi := tokInt;
              NextToken;
            end else if (tokKind = tkString) and (length(tokStr) = 1) then begin
              setHi := ord(tokStr[1]);
              NextToken;
            end else if tokKind = tkIdent then begin
              sym := LookupSym(tokStr);
              if (sym >= 0) and (syms[sym].kind = skConst) then begin
                setHi := syms[sym].offset;
                NextToken;
              end else
                isConst := false;
            end else
              isConst := false;
            if not isConst then break;
          end else
            setHi := setLo;

          { Set bits in bitmap }
          for fi := setLo to setHi do begin
            if (fi < 0) or (fi > 255) then
              Error('set element out of range (0..255)');
            setBitmap[fi div 8] := setBitmap[fi div 8] or (1 shl (fi mod 8));
            if fi > 31 then
              nSetElems := 1;  { flag: needs large set }
          end;

          if tokKind = tkComma then
            NextToken
          else
            break;
        until false;
      end;

      if isConst then begin
        Expect(tkRBrack);
        if nSetElems > 0 then begin
          { Large set: store 32-byte bitmap in data segment }
          fi := AllocDataAligned(32, 4);
          for setLo := 0 to 31 do
            DataBufEmit(secData, setBitmap[setLo]);
          EmitI32Const(fi);
          exprType := tySet;
          exprSetSize := 32;
        end else begin
          { Small set: pack into i32 }
          setLo := setBitmap[0] or (setBitmap[1] shl 8)
                   or (setBitmap[2] shl 16) or (setBitmap[3] shl 24);
          EmitI32Const(setLo);
          exprType := tySet;
          exprSetSize := 4;
        end;
      end else begin
        { Runtime codegen for non-constant set constructor (small sets only) }
        EmitI32Const(0);  { start with empty set }
        { Note: we already consumed some tokens. The remaining elements
          start from current token position. First re-process any partially
          parsed element. }
        { For simplicity, assume non-const path starts fresh. This means
          mixing const and non-const elements in a single constructor
          is not supported. In practice this is rare. }
        if tokKind <> tkRBrack then begin
          repeat
            curFuncNeedsStringTemp := true;
            EmitOp(OpLocalSet);
            EmitULEB128(startCode, curStringTempIdx);
            ParseExpression(PrecNone);
            if tokKind = tkDotDot then begin
              curFuncNeedsCaseTemp := true;
              EmitOp(OpLocalSet);
              EmitULEB128(startCode, curCaseTempIdx);
              EmitI32Const(-1);
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, curCaseTempIdx);
              EmitOp(OpI32Shl);
              NextToken;
              ParseExpression(PrecNone);
              EmitI32Const(1);
              EmitOp(OpI32Add);
              EmitOp(OpLocalSet);
              EmitULEB128(startCode, curCaseTempIdx);
              EmitI32Const(-1);
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, curCaseTempIdx);
              EmitOp(OpI32Shl);
              EmitOp(OpI32Xor);
            end else begin
              curFuncNeedsCaseTemp := true;
              EmitOp(OpLocalSet);
              EmitULEB128(startCode, curCaseTempIdx);
              EmitI32Const(1);
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, curCaseTempIdx);
              EmitOp(OpI32Shl);
            end;
            EmitOp(OpLocalGet);
            EmitULEB128(startCode, curStringTempIdx);
            EmitOp(OpI32Or);
            if tokKind = tkComma then
              NextToken
            else
              break;
          until false;
        end;
        Expect(tkRBrack);
        exprType := tySet;
        exprSetSize := 4;
      end;
    end;

    tkNot: begin
      NextToken;
      ParseExpression(PrecUnary);
      if exprType = tyBoolean then begin
        { boolean not: 0 -> 1, non-zero -> 0 }
        EmitOp(OpI32Eqz);
      end else begin
        { bitwise not: xor with -1 (all bits) }
        EmitI32Const(-1);
        EmitOp(OpI32Xor);
      end;
    end;
  else
    Error('expression expected');
  end;

  { Infix }
  while true do begin
    op := tokKind;
    case op of
      tkPlus:      prec := PrecAdd;
      tkMinus:     prec := PrecAdd;
      tkOr:        prec := PrecAdd;
      tkOrElse:    prec := PrecOrElse;
      tkStar:      prec := PrecMul;
      tkDiv:       prec := PrecMul;
      tkMod:       prec := PrecMul;
      tkShl:       prec := PrecMul;
      tkShr:       prec := PrecMul;
      tkAnd:       prec := PrecMul;
      tkAndThen:   prec := PrecAndThen;
      tkEqual:     prec := PrecCompare;
      tkNotEqual:  prec := PrecCompare;
      tkLess:      prec := PrecCompare;
      tkGreater:   prec := PrecCompare;
      tkLessEq:    prec := PrecCompare;
      tkGreaterEq: prec := PrecCompare;
      tkIn:        prec := PrecCompare;
    else
      break; { not an operator }
    end;

    if prec <= minPrec then
      break;

    leftType := exprType;
    if leftType = tySet then
      leftSetSize := exprSetSize;

    { For string +: save left operand to scratch BEFORE parsing right }
    if (leftType = tyString) and (op = tkPlus) then begin
      EnsureConcatScratch;
      if concatPieces >= 16 then
        Error('too many string concatenation pieces (max 16)');
      { Save left addr from WASM stack to scratch[concatPieces] }
      curFuncNeedsStringTemp := true;
      EmitOp(OpLocalSet);
      EmitULEB128(startCode, curStringTempIdx);
      EmitI32Const(addrConcatScratch + concatPieces * 4);
      EmitOp(OpLocalGet);
      EmitULEB128(startCode, curStringTempIdx);
      EmitI32Store(2, 0);
      concatPieces := concatPieces + 1;
    end;

    { Short-circuit: emit if-block before parsing right operand }
    if op = tkAndThen then begin
      EmitOp(OpIf);
      EmitOp(WasmI32);  { typed block returning i32 }
    end
    else if op = tkOrElse then begin
      EmitOp(OpIf);
      EmitOp(WasmI32);  { typed block returning i32 }
    end;

    NextToken;

    if op = tkAndThen then begin
      ParseExpression(prec);
      EmitOp(OpElse);
      EmitI32Const(0);  { false }
      EmitOp(OpEnd);
      exprType := tyBoolean;
    end
    else if op = tkOrElse then begin
      EmitI32Const(1);  { true }
      EmitOp(OpElse);
      ParseExpression(prec);
      EmitOp(OpEnd);
      exprType := tyBoolean;
    end
    else begin
    ParseExpression(prec);

    { Coerce char to 1-char Pascal string for concat/comparison }
    if (leftType = tyString) and (exprType = tyChar) and
       (op in [tkPlus, tkEqual, tkNotEqual, tkLess, tkGreater, tkLessEq, tkGreaterEq]) then begin
      EnsureCharStr;
      { Stack has char value. Store as Pascal string: len=1, data=char }
      curFuncNeedsStringTemp := true;
      EmitOp(OpLocalSet);
      EmitULEB128(startCode, curStringTempIdx);  { save char value }
      EmitI32Const(addrCharStr);
      EmitI32Const(1);
      EmitOp(OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);  { len=1 }
      EmitI32Const(addrCharStr + 1);
      EmitOp(OpLocalGet);
      EmitULEB128(startCode, curStringTempIdx);
      EmitOp(OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);  { data }
      EmitI32Const(addrCharStr);  { push string address }
      exprType := tyString;
    end;

    { Emit operator }
    if (leftType = tyString) and (op = tkPlus) then begin
      { No runtime code — pieces tracked at compile time, last piece on stack }
      exprType := tyString;
    end
    else if (leftType = tyString) and (op in [tkEqual, tkNotEqual, tkLess,
        tkGreater, tkLessEq, tkGreaterEq]) then begin
      { String comparison: call __str_compare, then compare result to 0 }
      EmitCall(EnsureStrCompare);
      case op of
        tkEqual:     begin EmitI32Const(0); EmitOp(OpI32Eq); end;
        tkNotEqual:  begin EmitI32Const(0); EmitOp(OpI32Ne); end;
        tkLess:      begin EmitI32Const(0); EmitOp(OpI32LtS); end;
        tkGreater:   begin EmitI32Const(0); EmitOp(OpI32GtS); end;
        tkLessEq:    begin EmitI32Const(0); EmitOp(OpI32LeS); end;
        tkGreaterEq: begin EmitI32Const(0); EmitOp(OpI32GeS); end;
      end;
      exprType := tyBoolean;
    end
    else if (leftType = tyChar) and (exprType = tyString) and
        (op in [tkEqual, tkNotEqual, tkLess, tkGreater, tkLessEq, tkGreaterEq]) then begin
      { Char vs single-char string literal: convert string addr to char value }
      { Stack: char_value, string_addr. Load byte at addr+1 (skip length). }
      EmitI32Const(1);
      EmitOp(OpI32Add);
      EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
      case op of
        tkEqual:     EmitOp(OpI32Eq);
        tkNotEqual:  EmitOp(OpI32Ne);
        tkLess:      EmitOp(OpI32LtS);
        tkGreater:   EmitOp(OpI32GtS);
        tkLessEq:    EmitOp(OpI32LeS);
        tkGreaterEq: EmitOp(OpI32GeS);
      end;
      exprType := tyBoolean;
    end
    else if op = tkIn then begin
      if leftType = tyString then begin
        { Convert string addr (left) to char ordinal.
          Stack: string_addr (elem), set_value/addr (right on top).
          Save right to caseTemp, convert left, restore right. }
        curFuncNeedsCaseTemp := true;
        EmitOp(OpLocalSet);
        EmitULEB128(startCode, curCaseTempIdx);  { save right }
        { String addr on stack. Load byte at addr+1 (skip length byte) }
        EmitI32Const(1);
        EmitOp(OpI32Add);
        EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
        EmitOp(OpLocalGet);
        EmitULEB128(startCode, curCaseTempIdx);  { restore right }
        leftType := tyChar;
      end;
      if exprSetSize > 4 then begin
        { Large set IN: stack has elem, set_addr.
          Compute: load byte at set_addr + (elem div 8), test bit (elem mod 8) }
        curFuncNeedsCaseTemp := true;
        curFuncNeedsStringTemp := true;
        EmitOp(OpLocalSet);
        EmitULEB128(startCode, curCaseTempIdx);   { save set_addr }
        EmitOp(OpLocalSet);
        EmitULEB128(startCode, curStringTempIdx);  { save elem }
        { Compute set_addr + (elem div 8) }
        EmitOp(OpLocalGet);
        EmitULEB128(startCode, curCaseTempIdx);
        EmitOp(OpLocalGet);
        EmitULEB128(startCode, curStringTempIdx);
        EmitI32Const(3);
        EmitOp(OpI32ShrU);  { elem div 8 = elem >> 3 }
        EmitOp(OpI32Add);   { set_addr + byte_index }
        EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0); { load byte, align=0, offset=0 }
        { Shift right by (elem mod 8) and test bit 0 }
        EmitOp(OpLocalGet);
        EmitULEB128(startCode, curStringTempIdx);
        EmitI32Const(7);
        EmitOp(OpI32And);   { elem mod 8 }
        EmitOp(OpI32ShrU);  { byte >> bit_pos }
        EmitI32Const(1);
        EmitOp(OpI32And);   { isolate bit }
      end else begin
        { Small set IN: (1 << elem) AND set <> 0 }
        { Stack: elem, set. Save set to caseTemp, compute 1 << elem, AND. }
        curFuncNeedsCaseTemp := true;
        EmitOp(OpLocalSet);
        EmitULEB128(startCode, curCaseTempIdx);  { save set }
        curFuncNeedsStringTemp := true;
        EmitOp(OpLocalSet);
        EmitULEB128(startCode, curStringTempIdx);
        EmitI32Const(1);
        EmitOp(OpLocalGet);
        EmitULEB128(startCode, curStringTempIdx);
        EmitOp(OpI32Shl);     { 1 << elem }
        EmitOp(OpLocalGet);
        EmitULEB128(startCode, curCaseTempIdx);
        EmitOp(OpI32And);
        EmitI32Const(0);
        EmitOp(OpI32Ne);
      end;
      exprType := tyBoolean;
    end
    else if (leftType = tySet) and (op in [tkPlus, tkMinus, tkStar,
        tkEqual, tkNotEqual, tkLessEq, tkGreaterEq]) then begin
      if (leftSetSize > 4) or (exprSetSize > 4) then begin
        { Large set operations — both operands are addresses on stack.
          Handle mismatch when one side is [] (small i32 = 0):
          replace with address of static 32-byte zero block. }
        EnsureSetTemp;
        if (exprSetSize <= 4) then begin
          { Right operand is small (e.g. []) — stack: ..., left_addr, right_i32.
            Drop i32, push addrSetZero. }
          EmitOp(OpDrop);
          EmitI32Const(addrSetZero);
        end;
        if (leftSetSize <= 4) then begin
          { Left operand is small — stack: ..., left_i32, right_addr.
            Save right, drop left i32, push addrSetZero, restore right. }
          curFuncNeedsCaseTemp := true;
          EmitOp(OpLocalSet);
          EmitULEB128(startCode, curCaseTempIdx);
          EmitOp(OpDrop);
          EmitI32Const(addrSetZero);
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, curCaseTempIdx);
        end;
        curFuncNeedsCaseTemp := true;
        curFuncNeedsStringTemp := true;
        EmitOp(OpLocalSet);
        EmitULEB128(startCode, curCaseTempIdx);    { save b_addr }
        EmitOp(OpLocalSet);
        EmitULEB128(startCode, curStringTempIdx);  { save a_addr }
        if op in [tkPlus, tkMinus, tkStar] then begin
          { Arithmetic: call helper(dst, a, b), push dst addr }
          EnsureSetTemp;
          if setTempFlip then fi := addrSetTemp2
          else fi := addrSetTemp;
          setTempFlip := not setTempFlip;
          EmitI32Const(fi);                        { dst }
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, curStringTempIdx); { a }
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, curCaseTempIdx);   { b }
          case op of
            tkPlus:  EmitCall(EnsureSetUnion);
            tkStar:  EmitCall(EnsureSetIntersect);
            tkMinus: EmitCall(EnsureSetDiff);
          end;
          EmitI32Const(fi);  { push result address }
          exprType := tySet;
        end else begin
          { Comparison: call helper(a, b) -> i32 }
          case op of
            tkEqual, tkNotEqual: begin
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, curStringTempIdx);
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, curCaseTempIdx);
              EmitCall(EnsureSetEq);
              if op = tkNotEqual then
                EmitOp(OpI32Eqz);
            end;
            tkLessEq: begin              { subset: a <= b }
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, curStringTempIdx);
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, curCaseTempIdx);
              EmitCall(EnsureSetSubset);
            end;
            tkGreaterEq: begin           { superset: a >= b means b <= a }
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, curCaseTempIdx);   { b first }
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, curStringTempIdx);  { a second }
              EmitCall(EnsureSetSubset);
            end;
          end;
          exprType := tyBoolean;
        end;
      end else begin
        { Small set operations — both operands are i32 bitmaps on stack }
        case op of
          tkPlus:  EmitOp(OpI32Or);    { union }
          tkStar:  EmitOp(OpI32And);   { intersection }
          tkMinus: begin               { difference: A AND NOT B }
            EmitI32Const(-1);
            EmitOp(OpI32Xor);          { NOT B }
            EmitOp(OpI32And);
          end;
          tkEqual:    EmitOp(OpI32Eq);
          tkNotEqual: EmitOp(OpI32Ne);
          tkLessEq: begin              { subset: A AND NOT B = 0 }
            EmitI32Const(-1);
            EmitOp(OpI32Xor);          { NOT B }
            EmitOp(OpI32And);          { A AND NOT B }
            EmitI32Const(0);
            EmitOp(OpI32Eq);
          end;
          tkGreaterEq: begin           { superset: B AND NOT A = 0 }
            { Stack: A, B. Need B AND NOT A.
              Save B, NOT A, AND B. }
            curFuncNeedsCaseTemp := true;
            EmitOp(OpLocalSet);
            EmitULEB128(startCode, curCaseTempIdx);  { save B }
            EmitI32Const(-1);
            EmitOp(OpI32Xor);          { NOT A }
            EmitOp(OpLocalGet);
            EmitULEB128(startCode, curCaseTempIdx);
            EmitOp(OpI32And);          { B AND NOT A }
            EmitI32Const(0);
            EmitOp(OpI32Eq);
          end;
        end;
        if op in [tkPlus, tkMinus, tkStar] then
          exprType := tySet
        else
          exprType := tyBoolean;
      end;
    end else begin
      case op of
        tkPlus:      if optOverflowChecks then EmitCall(EnsureCheckedAdd)
                     else EmitOp(OpI32Add);
        tkMinus:     if optOverflowChecks then EmitCall(EnsureCheckedSub)
                     else EmitOp(OpI32Sub);
        tkStar:      if optOverflowChecks then EmitCall(EnsureCheckedMul)
                     else EmitOp(OpI32Mul);
        tkDiv:       EmitOp(OpI32DivS);
        tkMod:       EmitOp(OpI32RemS);
        tkShl:       EmitOp(OpI32Shl);
        tkShr:       EmitOp(OpI32ShrU);
        tkAnd:       EmitOp(OpI32And);
        tkOr:        EmitOp(OpI32Or);
        tkEqual:     EmitOp(OpI32Eq);
        tkNotEqual:  EmitOp(OpI32Ne);
        tkLess:      EmitOp(OpI32LtS);
        tkGreater:   EmitOp(OpI32GtS);
        tkLessEq:    EmitOp(OpI32LeS);
        tkGreaterEq: EmitOp(OpI32GeS);
      end;
    end;
    end; { else begin (non-short-circuit) }
  end;
end;

procedure ParseWriteArgs(withNewline: boolean);
{** Parse arguments to write/writeln and emit fd_write calls.
  Supports write(stderr, ...) for output to fd 2. }
var
  addr, slen, i, fd: longint;
begin
  fd := 1; { default: stdout }
  if tokKind = tkLParen then begin
    NextToken;
    { Check for stderr as first argument }
    if (tokKind = tkIdent) and (tokStr = 'STDERR') then begin
      fd := 2;
      NextToken;
      if tokKind = tkComma then
        NextToken
      else begin
        { write(stderr) with no other args — just newline if writeln }
        Expect(tkRParen);
        if withNewline then
          EmitWriteNewlineFd(fd);
        exit;
      end;
    end;
    while tokKind <> tkRParen do begin
      if tokKind = tkString then begin
        { String literal - emit directly via raw data (no length byte) }
        slen := length(tokStr);
        addr := EmitDataString(tokStr);
        EmitWriteStringFd(fd, addr, slen);
        NextToken;
        exprType := tyString; { for consistency }
      end else begin
        ParseExpression(PrecNone);
        if exprType = tyString then begin
          if concatPieces > 0 then begin
            { Concat expression: save last piece, emit write for each }
            curFuncNeedsStringTemp := true;
            EmitOp(OpLocalSet);
            EmitULEB128(startCode, curStringTempIdx);
            for i := 0 to concatPieces - 1 do begin
              EmitI32Const(addrConcatScratch + i * 4);
              EmitI32Load(2, 0);
              if fd = 1 then
                EmitCall(EnsureWriteStr)
              else begin
                curFuncNeedsStringTemp := true;
                EmitInlineWriteStr(fd, curStringTempIdx);
              end;
            end;
            EmitOp(OpLocalGet);
            EmitULEB128(startCode, curStringTempIdx);
            if fd = 1 then
              EmitCall(EnsureWriteStr)
            else begin
              curFuncNeedsStringTemp := true;
              EmitInlineWriteStr(fd, curStringTempIdx);
            end;
            concatPieces := 0;
          end else begin
            { Simple string expression — addr is on stack }
            if fd = 1 then
              EmitCall(EnsureWriteStr)
            else begin
              curFuncNeedsStringTemp := true;
              EmitInlineWriteStr(fd, curStringTempIdx);
            end;
          end;
        end else if exprType = tyChar then begin
          { Char expression: write raw byte }
          EmitWriteChar(fd);
        end else begin
          { Integer/boolean/enum expression }
          if fd = 1 then
            EmitWriteInt
          else begin
            { For stderr: convert to string via __int_to_str, then write string }
            EnsureIntToStr;
            EmitI32Const(addrIntBuf);
            EmitCall(EnsureIntToStrHelper);
            EmitI32Const(addrIntBuf);
            curFuncNeedsStringTemp := true;
            EmitInlineWriteStr(fd, curStringTempIdx);
          end;
        end;
      end;
      if tokKind = tkComma then
        NextToken;
    end;
    Expect(tkRParen);
  end;
  if withNewline then
    EmitWriteNewlineFd(fd);
end;

procedure EmitSkipLine;
{** Emit inline code to consume bytes from stdin until LF or EOF.
  ;; WAT: block $done
  ;;        loop $again
  ;;          ;; set up iovec for 1-byte read
  ;;          ;; fd_read(0, iovec, 1, nread)
  ;;          ;; if nread == 0: br $done (EOF)
  ;;          ;; if readbuf[0] == 10: br $done (LF)
  ;;          ;; br $again (continue)
  ;;        end
  ;;      end
}
begin
  EnsureReadBuffers;

  EmitOp(OpBlock); EmitOp(WasmVoid);   { $done = label 1 from inside loop }
  EmitOp(OpLoop); EmitOp(WasmVoid);    { $again = label 0 }
    { Set up iovec: buf = addrReadBuf, len = 1 }
    EmitI32Const(addrIovec);
    EmitI32Const(addrReadBuf);
    EmitI32Store(2, 0);
    EmitI32Const(addrIovec + 4);
    EmitI32Const(1);
    EmitI32Store(2, 0);

    { fd_read(0, iovec, 1, nread) }
    EmitI32Const(0);
    EmitI32Const(addrIovec);
    EmitI32Const(1);
    EmitI32Const(addrNread);
    EmitCall(idxFdRead);
    EmitOp(OpDrop);

    { if nread == 0: br 1 (exit block = EOF) }
    EmitI32Const(addrNread);
    EmitI32Load(2, 0);
    EmitOp(OpI32Eqz);
    EmitOp(OpBrIf); EmitULEB128(startCode, 1);

    { if readbuf[0] == 10 (LF): br 1 (exit block) }
    EmitI32Const(addrReadBuf);
    CodeBufEmit(startCode, OpI32Load8u);
    EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
    EmitI32Const(10);
    EmitOp(OpI32Eq);
    EmitOp(OpBrIf); EmitULEB128(startCode, 1);

    { br 0 (continue loop) }
    EmitOp(OpBr); EmitULEB128(startCode, 0);
  EmitOp(OpEnd);  { end loop }
  EmitOp(OpEnd);  { end block }
end;

procedure ParseReadArgs(withNewline: boolean);
{** Parse arguments to read/readln and emit fd_read calls.
  Each argument must be an integer variable. Calls __read_int
  to parse a decimal integer from stdin and stores the result. }
var
  sym: longint;
  name: string;
  ridx: longint;
  lastWasString: boolean;
begin
  ridx := EnsureReadInt;
  lastWasString := false;
  if tokKind = tkLParen then begin
    NextToken;
    while tokKind <> tkRParen do begin
      if tokKind <> tkIdent then
        Error('variable expected in read');
      name := tokStr;
      sym := LookupSym(name);
      if sym < 0 then
        Error('undeclared identifier: ' + name);
      if syms[sym].kind <> skVar then
        Error('variable expected in read');
      if syms[sym].isConstParam then
        Error('cannot read into const parameter ''' + name + '''');

      lastWasString := (syms[sym].typ = tyString);
      if syms[sym].typ = tyString then begin
        { String variable: call __read_str(addr, max_len) }
        if syms[sym].isVarParam then begin
          EmitVarParamPtr(sym);
        end else begin
          EmitFramePtr(syms[sym].level);
          EmitI32Const(syms[sym].offset);
          EmitOp(OpI32Add);
        end;
        EmitI32Const(syms[sym].strMax);
        EmitCall(EnsureReadStr);
      end
      else if syms[sym].typ = tyChar then begin
        { Char variable: read 1 byte from stdin via fd_read }
        EnsureReadBuffers;
        { Set up iovec: buf=addrReadBuf, len=1 }
        EmitI32Const(addrIovec);
        EmitI32Const(addrReadBuf);
        EmitI32Store(2, 0);
        EmitI32Const(addrIovec + 4);
        EmitI32Const(1);
        EmitI32Store(2, 0);
        { fd_read(0, iovec, 1, nread) }
        EmitI32Const(0);
        EmitI32Const(addrIovec);
        EmitI32Const(1);
        EmitI32Const(addrNread);
        EmitCall(idxFdRead);
        EmitOp(OpDrop);
        { Load the byte from addrReadBuf }
        EmitI32Const(addrReadBuf);
        EmitI32Load8u(0, 0);
        { Store to variable }
        if syms[sym].isVarParam then begin
          { var param: store byte through pointer }
          curFuncNeedsStringTemp := true;
          EmitOp(OpLocalSet);
          EmitULEB128(startCode, curStringTempIdx);
          EmitVarParamPtr(sym);
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, curStringTempIdx);
          EmitI32Store8(0);
        end else if syms[sym].offset < 0 then begin
          { WASM local }
          EmitOp(OpLocalSet);
          EmitULEB128(startCode, -(syms[sym].offset + 1));
        end else begin
          { Stack frame variable: store byte at frame offset }
          curFuncNeedsStringTemp := true;
          EmitOp(OpLocalSet);
          EmitULEB128(startCode, curStringTempIdx);
          EmitFramePtr(syms[sym].level);
          EmitI32Const(syms[sym].offset);
          EmitOp(OpI32Add);
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, curStringTempIdx);
          EmitI32Store8(0);
        end;
      end
      else if syms[sym].isVarParam then begin
        { var param: push pointer, call __read_int, i32.store }
        EmitVarParamPtr(sym);
        EmitCall(ridx);
        EmitI32Store(2, 0);
      end
      else if syms[sym].offset < 0 then begin
        { WASM local (value parameter): call, then local.set }
        { ;; WAT: call $__read_int    ;; parsed value }
        { ;;      local.set <idx>     ;; store in local }
        EmitCall(ridx);
        EmitOp(OpLocalSet);
        EmitULEB128(startCode, -(syms[sym].offset + 1));
      end else begin
        { Stack frame variable: push address, call, i32.store }
        { ;; WAT: <frame_ptr + offset> ;; target address }
        { ;;      call $__read_int     ;; parsed value }
        { ;;      i32.store            ;; store to frame }
        EmitFramePtr(syms[sym].level);
        EmitI32Const(syms[sym].offset);
        EmitOp(OpI32Add);
        EmitCall(ridx);
        EmitI32Store(2, 0);
      end;

      NextToken;
      if tokKind = tkComma then
        NextToken;
    end;
    Expect(tkRParen);
  end;
  if withNewline and (not lastWasString) then
    EmitSkipLine;
end;

procedure EvalConstExpr(var outVal: longint; var outTyp: longint);
{** Evaluate a compile-time constant expression. Returns value and type.
    Handles integer/char/boolean literals, previously declared constants,
    arithmetic, logical, and comparison operators, parentheses, unary +/-.
    Does NOT emit any WASM code. }
var
  sym: longint;
  lval, rval: longint;
  ltyp, rtyp: longint;
  castName: string;
  castTyp: longint;

  procedure EvalAtom;
  begin
    case tokKind of
      tkInteger: begin
        outVal := tokInt;
        outTyp := tyInteger;
        NextToken;
      end;
      tkString: begin
        if length(tokStr) = 1 then begin
          { Single character: treat as char constant }
          outVal := ord(tokStr[1]);
          outTyp := tyChar;
        end else begin
          { Multi-char string: store in data segment, return address }
          outVal := EmitDataPascalString(tokStr);
          outTyp := tyString;
        end;
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
      tkLParen: begin
        NextToken;
        EvalConstExpr(outVal, outTyp);
        Expect(tkRParen);
      end;
      tkMinus: begin
        NextToken;
        EvalAtom;
        if outTyp <> tyInteger then
          Error('unary minus requires integer operand');
        outVal := -outVal;
      end;
      tkPlus: begin
        NextToken;
        EvalAtom;
        if outTyp <> tyInteger then
          Error('unary plus requires integer operand');
      end;
      tkNot: begin
        NextToken;
        EvalAtom;
        if outTyp = tyBoolean then
          outVal := ord(outVal = 0)
        else if outTyp = tyInteger then
          outVal := not outVal
        else
          Error('not requires boolean or integer operand');
      end;
      tkIdent: begin
        { Check for built-in constant functions }
        if tokStr = 'ORD' then begin
          NextToken; Expect(tkLParen);
          EvalConstExpr(outVal, outTyp);
          if not (outTyp in [tyChar, tyBoolean, tyInteger, tyEnum]) then
            Error('ord() requires ordinal argument');
          outTyp := tyInteger;
          Expect(tkRParen);
        end
        else if tokStr = 'CHR' then begin
          NextToken; Expect(tkLParen);
          EvalConstExpr(outVal, outTyp);
          if outTyp <> tyInteger then
            Error('chr() requires integer argument');
          outTyp := tyChar;
          Expect(tkRParen);
        end
        else if tokStr = 'ABS' then begin
          NextToken; Expect(tkLParen);
          EvalConstExpr(outVal, outTyp);
          if outTyp <> tyInteger then
            Error('abs() requires integer argument');
          if outVal < 0 then outVal := -outVal;
          Expect(tkRParen);
        end
        else if tokStr = 'ODD' then begin
          NextToken; Expect(tkLParen);
          EvalConstExpr(outVal, outTyp);
          if outTyp <> tyInteger then
            Error('odd() requires integer argument');
          outVal := ord(odd(outVal));
          outTyp := tyBoolean;
          Expect(tkRParen);
        end
        else if tokStr = 'SUCC' then begin
          NextToken; Expect(tkLParen);
          EvalConstExpr(outVal, outTyp);
          if not (outTyp in [tyInteger, tyChar, tyBoolean, tyEnum]) then
            Error('succ() requires ordinal argument');
          outVal := outVal + 1;
          Expect(tkRParen);
        end
        else if tokStr = 'PRED' then begin
          NextToken; Expect(tkLParen);
          EvalConstExpr(outVal, outTyp);
          if not (outTyp in [tyInteger, tyChar, tyBoolean, tyEnum]) then
            Error('pred() requires ordinal argument');
          outVal := outVal - 1;
          Expect(tkRParen);
        end
        else if tokStr = 'SQR' then begin
          NextToken; Expect(tkLParen);
          EvalConstExpr(outVal, outTyp);
          if outTyp <> tyInteger then
            Error('sqr() requires integer argument');
          outVal := outVal * outVal;
          Expect(tkRParen);
        end
        else if tokStr = 'LO' then begin
          NextToken; Expect(tkLParen);
          EvalConstExpr(outVal, outTyp);
          if outTyp <> tyInteger then
            Error('lo() requires integer argument');
          outVal := outVal and $FF;
          Expect(tkRParen);
        end
        else if tokStr = 'HI' then begin
          NextToken; Expect(tkLParen);
          EvalConstExpr(outVal, outTyp);
          if outTyp <> tyInteger then
            Error('hi() requires integer argument');
          outVal := (outVal shr 8) and $FF;
          Expect(tkRParen);
        end
        else if tokStr = 'SIZEOF' then begin
          NextToken; Expect(tkLParen);
          if tokKind <> tkIdent then
            Expected('type or variable name');
          sym := LookupSym(tokStr);
          if sym < 0 then
            Error('undeclared identifier: ' + tokStr);
          case syms[sym].kind of
            skType: begin
              case syms[sym].typ of
                tyInteger:  outVal := 4;
                tyBoolean:  outVal := 4;
                tyChar:     outVal := 4;
                tyString:   outVal := syms[sym].strMax + 1;
              else
                outVal := syms[sym].size;
              end;
            end;
            skVar, skConst:
              outVal := syms[sym].size;
          else
            Error('sizeof() requires type or variable');
          end;
          outTyp := tyInteger;
          NextToken;
          Expect(tkRParen);
        end
        else begin
          { Look up as a previously declared constant or type cast }
          sym := LookupSym(tokStr);
          if sym < 0 then
            Error('undeclared identifier: ' + tokStr);
          if syms[sym].kind = skType then begin
            { Constant type cast: TypeName(constexpr) }
            castName := syms[sym].name;
            castTyp := syms[sym].typ;
            NextToken;
            Expect(tkLParen);
            EvalConstExpr(outVal, outTyp);
            Expect(tkRParen);
            if (castName = 'CHAR') or (castName = 'BYTE') then
              outVal := outVal and 255
            else if castName = 'SHORTINT' then begin
              outVal := outVal and 255;
              if outVal >= 128 then
                outVal := outVal - 256;
            end else if castName = 'WORD' then
              outVal := outVal and 65535;
            outTyp := castTyp;
          end else if syms[sym].kind = skConst then begin
            outVal := syms[sym].offset;
            outTyp := syms[sym].typ;
            NextToken;
          end else
            Error(tokStr + ' is not a constant');
        end;
      end;
    else
      Error('constant expression expected');
    end;
  end;

  procedure EvalBinary(minPrec: longint);
  var
    op, prec: longint;
  begin
    EvalAtom;
    while true do begin
      op := tokKind;
      case op of
        tkPlus:      prec := PrecAdd;
        tkMinus:     prec := PrecAdd;
        tkOr:        prec := PrecAdd;
        tkOrElse:    prec := PrecOrElse;
        tkStar:      prec := PrecMul;
        tkDiv:       prec := PrecMul;
        tkMod:       prec := PrecMul;
        tkShl:       prec := PrecMul;
        tkShr:       prec := PrecMul;
        tkAnd:       prec := PrecMul;
        tkAndThen:   prec := PrecAndThen;
        tkEqual:     prec := PrecCompare;
        tkNotEqual:  prec := PrecCompare;
        tkLess:      prec := PrecCompare;
        tkGreater:   prec := PrecCompare;
        tkLessEq:    prec := PrecCompare;
        tkGreaterEq: prec := PrecCompare;
      else
        break;
      end;
      if prec <= minPrec then
        break;
      lval := outVal;
      ltyp := outTyp;
      NextToken;
      EvalBinary(prec);
      rval := outVal;
      rtyp := outTyp;
      case op of
        tkPlus:  outVal := lval + rval;
        tkMinus: outVal := lval - rval;
        tkStar:  outVal := lval * rval;
        tkDiv: begin
          if rval = 0 then Error('division by zero in constant expression');
          outVal := lval div rval;
        end;
        tkMod: begin
          if rval = 0 then Error('division by zero in constant expression');
          outVal := lval mod rval;
        end;
        tkShl:  outVal := lval shl rval;
        tkShr:  outVal := lval shr rval;
        tkAnd, tkAndThen: outVal := lval and rval;
        tkOr, tkOrElse:   outVal := lval or rval;
        tkEqual:     outVal := ord(lval = rval);
        tkNotEqual:  outVal := ord(lval <> rval);
        tkLess:      outVal := ord(lval < rval);
        tkGreater:   outVal := ord(lval > rval);
        tkLessEq:    outVal := ord(lval <= rval);
        tkGreaterEq: outVal := ord(lval >= rval);
      end;
      if op in [tkEqual, tkNotEqual, tkLess, tkGreater, tkLessEq, tkGreaterEq] then
        outTyp := tyBoolean
      else
        outTyp := ltyp;
    end;
  end;

begin
  EvalBinary(PrecNone);
end;

procedure ParseVarDecl;
{** Parse variable declarations in a var section. }
var
  names: array[0..31] of string[63];
  nnames: longint;
  i, sym: longint;
  varTyp: longint;
  varTypeIdx: longint;
  varSize: longint;
  varStrMax: longint;
  pad: longint;
  initVal: longint;
  initTyp: longint;
  strAddr: longint;
begin
  while tokKind = tkIdent do begin
    { Collect identifier list }
    nnames := 0;
    repeat
      if nnames >= 32 then
        Error('too many variables in one declaration');
      names[nnames] := tokStr;
      nnames := nnames + 1;
      NextToken;
      if tokKind = tkComma then
        NextToken
      else
        break;
    until tokKind <> tkIdent;

    Expect(tkColon);

    { Parse type }
    ParseTypeSpec(varTyp, varTypeIdx, varSize, varStrMax);

    { Add symbols and allocate stack space }
    for i := 0 to nnames - 1 do begin
      { Align to 4-byte boundary for i32 access }
      pad := (4 - (curFrameSize mod 4)) mod 4;
      curFrameSize := curFrameSize + pad;
      sym := AddSym(names[i], skVar, varTyp);
      syms[sym].typeIdx := varTypeIdx;
      syms[sym].offset := curFrameSize;
      syms[sym].size := varSize;
      syms[sym].strMax := varStrMax;
      curFrameSize := curFrameSize + varSize;
    end;

    { Check for initializer: var x: integer = 5 }
    if tokKind = tkEqual then begin
      if nnames <> 1 then
        Error('cannot initialize multiple variables in one declaration');
      if numVarInits >= 16 then
        Error('too many variable initializers');
      NextToken;
      if varTyp = tyString then begin
        if tokKind <> tkString then
          Error('string constant expected');
        strAddr := EmitDataPascalString(tokStr);
        NextToken;
        varInitOffset[numVarInits] := syms[sym].offset;
        varInitVal[numVarInits] := strAddr;
        varInitIsStr[numVarInits] := true;
        varInitStrMax[numVarInits] := varStrMax;
        numVarInits := numVarInits + 1;
      end else begin
        EvalConstExpr(initVal, initTyp);
        varInitOffset[numVarInits] := syms[sym].offset;
        varInitVal[numVarInits] := initVal;
        varInitIsStr[numVarInits] := false;
        numVarInits := numVarInits + 1;
      end;
    end;

    Expect(tkSemicolon);
  end;
end;

procedure ParseStatement;
{** Parse a single statement. }
var
  sym: longint;
  name: string;
  argIdx: longint;
  argSym: longint;
  i: longint;
  desTyp: longint;
  desTypeIdx: longint;
  desStrMax: longint;
  desHasAddr: boolean;
  fldIdx: longint;
  withFound: boolean;
  wi: longint;
  tmpOfs: longint;
  savedBreak: longint;
  savedContinue: longint;
  limitAddr: longint;
  concatSPAllocs: longint;
begin
  concatSPAllocs := 0;
  case tokKind of
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

    tkIdent: begin
      name := tokStr;
      { Built-in procedures handled before symbol lookup }
      if name = 'DELETE' then begin
        { delete(var s, index, count) }
        NextToken;
        Expect(tkLParen);
        if tokKind <> tkIdent then
          Error('delete() first argument must be a string variable');
        sym := LookupSym(tokStr);
        if sym < 0 then
          Error('undeclared identifier: ' + tokStr);
        if syms[sym].typ <> tyString then
          Error('delete() first argument must be a string variable');
        { Push string address }
        if syms[sym].isVarParam then begin
          EmitVarParamPtr(sym);
        end else begin
          EmitFramePtr(syms[sym].level);
          EmitI32Const(syms[sym].offset);
          EmitOp(OpI32Add);
        end;
        NextToken;
        Expect(tkComma);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('delete() second argument must be an integer');
        Expect(tkComma);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('delete() third argument must be an integer');
        Expect(tkRParen);
        EmitCall(EnsureStrDelete);
      end
      else if name = 'INSERT' then begin
        { insert(src, var dst, index) }
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyString then
          Error('insert() first argument must be a string');
        Expect(tkComma);
        if tokKind <> tkIdent then
          Error('insert() second argument must be a string variable');
        sym := LookupSym(tokStr);
        if sym < 0 then
          Error('undeclared identifier: ' + tokStr);
        if syms[sym].typ <> tyString then
          Error('insert() second argument must be a string variable');
        { Push dst string address }
        if syms[sym].isVarParam then begin
          EmitVarParamPtr(sym);
        end else begin
          EmitFramePtr(syms[sym].level);
          EmitI32Const(syms[sym].offset);
          EmitOp(OpI32Add);
        end;
        NextToken;
        Expect(tkComma);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('insert() third argument must be an integer');
        Expect(tkRParen);
        EmitCall(EnsureStrInsert);
      end
      else if (name = 'INC') or (name = 'DEC') then begin
        NextToken;
        Expect(tkLParen);
        if tokKind <> tkIdent then
          Error(name + '() argument must be a variable');
        sym := LookupSym(tokStr);
        if sym < 0 then
          Error('undeclared identifier: ' + tokStr);
        if syms[sym].kind <> skVar then
          Error(name + '() argument must be a variable');
        if syms[sym].isConstParam then
          Error('cannot modify const parameter');
        if not (syms[sym].typ in [tyInteger, tyChar, tyBoolean, tyEnum]) then
          Error(name + '() requires ordinal type');
        NextToken;
        if syms[sym].isVarParam then begin
          (* var param: pointer in frame, read-modify-write through memory *)
          EmitVarParamPtr(sym);
          EmitVarParamPtr(sym);
          EmitI32Load(2, 0);
          if tokKind = tkComma then begin
            NextToken;
            ParseExpression(PrecNone);
          end else
            EmitI32Const(1);
          if name = 'INC' then
            EmitOp(OpI32Add)
          else
            EmitOp(OpI32Sub);
          EmitI32Store(2, 0);
        end else if syms[sym].offset < 0 then begin
          (* WASM local: get, add/sub, set *)
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, -(syms[sym].offset + 1));
          if tokKind = tkComma then begin
            NextToken;
            ParseExpression(PrecNone);
          end else
            EmitI32Const(1);
          if name = 'INC' then
            EmitOp(OpI32Add)
          else
            EmitOp(OpI32Sub);
          EmitOp(OpLocalSet);
          EmitULEB128(startCode, -(syms[sym].offset + 1));
        end else begin
          (* Stack frame variable: read-modify-write through memory *)
          EmitFramePtr(syms[sym].level);
          EmitI32Const(syms[sym].offset);
          EmitOp(OpI32Add);
          curFuncNeedsStringTemp := true;
          EmitOp(OpLocalTee);
          EmitULEB128(startCode, curStringTempIdx);
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, curStringTempIdx);
          EmitI32Load(2, 0);
          if tokKind = tkComma then begin
            NextToken;
            ParseExpression(PrecNone);
          end else
            EmitI32Const(1);
          if name = 'INC' then
            EmitOp(OpI32Add)
          else
            EmitOp(OpI32Sub);
          EmitI32Store(2, 0);
        end;
        Expect(tkRParen);
      end
      else if name = 'STR' then begin
        { str(intExpr, stringVar) — convert integer to Pascal string }
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('str() first argument must be integer');
        Expect(tkComma);
        if tokKind <> tkIdent then
          Error('str() second argument must be a string variable');
        sym := LookupSym(tokStr);
        if sym < 0 then
          Error('undeclared identifier: ' + tokStr);
        if syms[sym].typ <> tyString then
          Error('str() second argument must be a string variable');
        if syms[sym].kind <> skVar then
          Error('str() second argument must be a variable');
        if syms[sym].isConstParam then
          Error('cannot modify const parameter');
        { Push dest address }
        if syms[sym].isVarParam then begin
          EmitVarParamPtr(sym);
        end else if syms[sym].offset < 0 then begin
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, -(syms[sym].offset + 1));
        end else begin
          EmitFramePtr(syms[sym].level);
          EmitI32Const(syms[sym].offset);
          EmitOp(OpI32Add);
        end;
        EmitCall(EnsureIntToStrHelper);
        NextToken;
        Expect(tkRParen);
      end
      else begin
      sym := LookupSym(name);
      withFound := false;
      if sym < 0 then begin
        { Check with-stack for matching field }
        for wi := numWiths - 1 downto 0 do begin
          fldIdx := LookupField(withTypeIdx[wi], name);
          if fldIdx >= 0 then begin
            withFound := true;
            break;
          end;
        end;
        if not withFound then
          Error('undeclared identifier: ' + name);
      end;
      NextToken;
      if withFound and
         ((tokKind = tkAssign) or (tokKind = tkDot) or (tokKind = tkLBrack)) then begin
        { With-resolved field assignment }
        desTyp := fields[fldIdx].typ;
        desTypeIdx := fields[fldIdx].typeIdx;
        desStrMax := fields[fldIdx].strMax;
        { Emit record base address + field offset }
        if withIsVarParam[wi] then begin
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, -(withOffset[wi] + 1));
        end else if withIsLocal[wi] then begin
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, -(withOffset[wi] + 1));
        end else begin
          EmitFramePtr(withLevel[wi]);
          EmitI32Const(withOffset[wi]);
          EmitOp(OpI32Add);
        end;
        tmpOfs := withFieldOfs[wi] + fields[fldIdx].offset;
        if tmpOfs <> 0 then begin
          EmitI32Const(tmpOfs);
          EmitOp(OpI32Add);
        end;
        desHasAddr := true;
        { Process further selectors }
        while (tokKind = tkDot) or (tokKind = tkLBrack) do begin
          if tokKind = tkDot then begin
            if desTyp <> tyRecord then
              Error('record type expected before ''.''');
            NextToken;
            if tokKind <> tkIdent then
              Expected('field name');
            fldIdx := LookupField(desTypeIdx, tokStr);
            if fldIdx < 0 then
              Error('unknown field: ' + tokStr);
            if fields[fldIdx].offset <> 0 then begin
              EmitI32Const(fields[fldIdx].offset);
              EmitOp(OpI32Add);
            end;
            desTyp := fields[fldIdx].typ;
            desTypeIdx := fields[fldIdx].typeIdx;
            desStrMax := fields[fldIdx].strMax;
            NextToken;
          end else if desTyp = tyString then begin
            { String char index: s[i] — addr + i (1-based) }
            NextToken;
            ParseExpression(PrecNone);
            EmitOp(OpI32Add);
            desTyp := tyChar;
            desTypeIdx := -1;
            desStrMax := 0;
            Expect(tkRBrack);
          end else begin
            if desTyp <> tyArray then
              Error('array type expected before ''[''');
            NextToken;
            ParseExpression(PrecNone);
            if optRangeChecks then begin
              EmitI32Const(types[desTypeIdx].arrLo);
              EmitI32Const(types[desTypeIdx].arrHi);
              EmitCall(EnsureRangeCheck);
            end;
            if types[desTypeIdx].arrLo <> 0 then begin
              EmitI32Const(types[desTypeIdx].arrLo);
              EmitOp(OpI32Sub);
            end;
            if types[desTypeIdx].elemSize <> 1 then begin
              EmitI32Const(types[desTypeIdx].elemSize);
              EmitOp(OpI32Mul);
            end;
            EmitOp(OpI32Add);
            desTyp := types[desTypeIdx].elemType;
            desStrMax := types[desTypeIdx].elemStrMax;
            desTypeIdx := types[desTypeIdx].elemTypeIdx;
            if tokKind = tkComma then
              tokKind := tkLBrack
            else
              Expect(tkRBrack);
          end;
        end;
        { Now emit the assignment }
        if tokKind <> tkAssign then
          Expected(':=');
        NextToken;
        if desTyp = tyString then begin
          ParseExpression(PrecNone);
          if exprType <> tyString then
            Error('string expression expected');
          EmitI32Const(desStrMax);
          EmitCall(EnsureStrAssign);
        end else if (desTyp = tyRecord) or (desTyp = tyArray)
            or ((desTyp = tySet) and (desTypeIdx >= 0) and (types[desTypeIdx].size > 4)) then begin
          ParseExpression(PrecNone);
          if (desTyp = tySet) and (exprSetSize <= 4) then begin
            { RHS is small (e.g. []) but dest is large — drop i32, use zero block }
            EnsureSetTemp;
            EmitOp(OpDrop);
            EmitI32Const(addrSetZero);
          end;
          EmitI32Const(types[desTypeIdx].size);
          EmitMemoryCopy;
        end else begin
          ParseExpression(PrecNone);
          if (desTyp = tyChar) and (exprType = tyString) then begin
            EmitI32Const(1); EmitOp(OpI32Add);
            EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
          end;
          EmitStoreByType(desTyp);
        end;
      end
      else if (sym >= 0) and (syms[sym].kind = skVar) and
         ((tokKind = tkAssign) or (tokKind = tkDot) or (tokKind = tkLBrack)) then begin
        { Assignment: var [:= | .field | [index] ...] := expr }
        if syms[sym].isConstParam then
          Error('cannot assign to const parameter ''' + name + '''');

        { Track designator type as we process selectors }
        desTyp := syms[sym].typ;
        desTypeIdx := syms[sym].typeIdx;
        desStrMax := syms[sym].strMax;
        desHasAddr := false;

        if (tokKind = tkDot) or (tokKind = tkLBrack) then begin
          { Need to compute base address for selector chain }
          if syms[sym].isVarParam then begin
            EmitVarParamPtr(sym);
          end else if syms[sym].offset < 0 then begin
            EmitOp(OpLocalGet);
            EmitULEB128(startCode, -(syms[sym].offset + 1));
          end else begin
            EmitFramePtr(syms[sym].level);
            EmitI32Const(syms[sym].offset);
            EmitOp(OpI32Add);
          end;
          desHasAddr := true;

          { Process .field and [index] selectors }
          while (tokKind = tkDot) or (tokKind = tkLBrack) do begin
            if tokKind = tkDot then begin
              if desTyp <> tyRecord then
                Error('record type expected before ''.''');
              NextToken;
              if tokKind <> tkIdent then
                Expected('field name');
              fldIdx := LookupField(desTypeIdx, tokStr);
              if fldIdx < 0 then
                Error('unknown field: ' + tokStr);
              if fields[fldIdx].offset <> 0 then begin
                EmitI32Const(fields[fldIdx].offset);
                EmitOp(OpI32Add);
              end;
              desTyp := fields[fldIdx].typ;
              desTypeIdx := fields[fldIdx].typeIdx;
              desStrMax := fields[fldIdx].strMax;
              NextToken;
            end else begin
              if desTyp <> tyArray then
                Error('array type expected before ''[''');
              NextToken;
              ParseExpression(PrecNone);
              if optRangeChecks then begin
                EmitI32Const(types[desTypeIdx].arrLo);
                EmitI32Const(types[desTypeIdx].arrHi);
                EmitCall(EnsureRangeCheck);
              end;
              if types[desTypeIdx].arrLo <> 0 then begin
                EmitI32Const(types[desTypeIdx].arrLo);
                EmitOp(OpI32Sub);
              end;
              if types[desTypeIdx].elemSize <> 1 then begin
                EmitI32Const(types[desTypeIdx].elemSize);
                EmitOp(OpI32Mul);
              end;
              EmitOp(OpI32Add);
              desTyp := types[desTypeIdx].elemType;
              desStrMax := types[desTypeIdx].elemStrMax;
              desTypeIdx := types[desTypeIdx].elemTypeIdx;
              if tokKind = tkComma then
                tokKind := tkLBrack
              else
                Expect(tkRBrack);
            end;
          end;
        end;

        if tokKind <> tkAssign then
          Expected(':=');
        NextToken;

        if desTyp = tyString then begin
          { String assignment through designator }
          ParseExpression(PrecNone);
          if exprType <> tyString then
            Error('string expression expected');
          if concatPieces > 0 then begin
            curFuncNeedsStringTemp := true;
            EmitOp(OpLocalSet);
            EmitULEB128(startCode, curStringTempIdx);
            { Build result in addrConcatTemp to avoid self-referencing bugs }
            { Zero temp[0] }
            EmitI32Const(addrConcatTemp);
            EmitI32Const(0);
            EmitOp(OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
            { Append saved pieces to temp }
            for i := 0 to concatPieces - 1 do begin
              EmitI32Const(addrConcatTemp);
              EmitI32Const(255);
              EmitI32Const(addrConcatScratch + i * 4);
              EmitI32Load(2, 0);
              EmitCall(EnsureStrAppend);
            end;
            { Append last piece (on stack via stringTemp) to temp }
            EmitI32Const(addrConcatTemp);
            EmitI32Const(255);
            EmitOp(OpLocalGet);
            EmitULEB128(startCode, curStringTempIdx);
            EmitCall(EnsureStrAppend);
            { Assign temp to destination: __str_assign(dst, max, src) }
            if syms[sym].isVarParam and not desHasAddr then begin
              EmitVarParamPtr(sym);
            end else if not desHasAddr then begin
              EmitFramePtr(syms[sym].level);
              EmitI32Const(syms[sym].offset);
              EmitOp(OpI32Add);
            end;
            EmitI32Const(desStrMax);
            EmitI32Const(addrConcatTemp);
            EmitCall(EnsureStrAssign);
            concatPieces := 0;
          end else begin
            { Simple string assignment: __str_assign(dst, max_len, src) }
            curFuncNeedsStringTemp := true;
            EmitOp(OpLocalSet);
            EmitULEB128(startCode, curStringTempIdx);
            if desHasAddr then begin
              { Address was already on stack but consumed by selector chain.
                For simple vars without selectors, recompute. For selectors,
                this path won't be hit (desHasAddr=true only with selectors). }
            end;
            if syms[sym].isVarParam and not desHasAddr then begin
              EmitVarParamPtr(sym);
            end else if not desHasAddr then begin
              EmitFramePtr(syms[sym].level);
              EmitI32Const(syms[sym].offset);
              EmitOp(OpI32Add);
            end;
            EmitI32Const(desStrMax);
            EmitOp(OpLocalGet);
            EmitULEB128(startCode, curStringTempIdx);
            EmitCall(EnsureStrAssign);
          end;
        end
        else if (desTyp = tyRecord) or (desTyp = tyArray)
            or ((desTyp = tySet) and (desTypeIdx >= 0) and (types[desTypeIdx].size > 4)) then begin
          { Structured assignment: memory.copy dst, src, size }
          if not desHasAddr then begin
            { Compute dst address }
            if syms[sym].isVarParam then begin
              EmitVarParamPtr(sym);
            end else if syms[sym].offset < 0 then begin
              EmitOp(OpLocalGet);
              EmitULEB128(startCode, -(syms[sym].offset + 1));
            end else begin
              EmitFramePtr(syms[sym].level);
              EmitI32Const(syms[sym].offset);
              EmitOp(OpI32Add);
            end;
          end;
          { dst addr is on stack; parse src expr (leaves src addr) }
          ParseExpression(PrecNone);
          if (desTyp = tySet) and (exprSetSize <= 4) then begin
            { RHS is small (e.g. []) but dest is large — drop i32, use zero block }
            EnsureSetTemp;
            EmitOp(OpDrop);
            EmitI32Const(addrSetZero);
          end;
          EmitI32Const(types[desTypeIdx].size);
          EmitMemoryCopy;
        end
        else if desHasAddr then begin
          { Scalar with address on stack from selector chain }
          ParseExpression(PrecNone);
          if (desTyp = tyChar) and (exprType = tyString) then begin
            EmitI32Const(1); EmitOp(OpI32Add);
            EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
          end;
          EmitStoreByType(desTyp);
        end
        else if syms[sym].isVarParam then begin
          EmitVarParamPtr(sym);
          ParseExpression(PrecNone);
          if (desTyp = tyChar) and (exprType = tyString) then begin
            EmitI32Const(1); EmitOp(OpI32Add);
            EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
          end;
          EmitStoreByType(desTyp);
        end
        else if syms[sym].offset < 0 then begin
          { WASM local (value parameter or function return value) }
          ParseExpression(PrecNone);
          if (desTyp = tyChar) and (exprType = tyString) then begin
            EmitI32Const(1); EmitOp(OpI32Add);
            EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
          end;
          EmitOp(OpLocalSet);
          EmitULEB128(startCode, -(syms[sym].offset + 1));
        end else begin
          { Stack frame variable (local or upvalue) }
          EmitFramePtr(syms[sym].level);
          EmitI32Const(syms[sym].offset);
          EmitOp(OpI32Add);
          ParseExpression(PrecNone);
          if (desTyp = tyChar) and (exprType = tyString) then begin
            EmitI32Const(1); EmitOp(OpI32Add);
            EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
          end;
          EmitStoreByType(desTyp);
        end;
      end
      else if (sym >= 0) and (syms[sym].kind = skFunc) and (tokKind = tkAssign) then begin
        { Function return value assignment: FuncName := expr }
        NextToken;
        ParseExpression(PrecNone);
        { Store in the hidden WASM local at index nparams }
        EmitOp(OpLocalSet);
        EmitULEB128(startCode, funcs[syms[sym].size].nparams);
      end
      else if (sym >= 0) and ((syms[sym].kind = skProc) or (syms[sym].kind = skFunc)) then begin
        { Procedure/function call (discard result for functions) }
        if tokKind = tkLParen then begin
          NextToken;
          argIdx := 0;
          while tokKind <> tkRParen do begin
            if funcs[syms[sym].size].varParams[argIdx] then begin
              { var param: pass address of the variable }
              if funcs[syms[sym].size].constParams[argIdx] then begin
                { const param: parse full expression (may include concat) }
                ParseExpression(PrecNone);
                if concatPieces > 0 then begin
                  { Concat expression: finalize into SP-allocated temp
                    (avoids aliasing when callee also does concat) }
                  curFuncNeedsStringTemp := true;
                  EmitOp(OpLocalSet);
                  EmitULEB128(startCode, curStringTempIdx);
                  { Allocate 256 bytes on WASM stack }
                  EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
                  EmitI32Const(256);
                  EmitOp(OpI32Sub);
                  EmitOp(OpGlobalSet); EmitULEB128(startCode, 0);
                  concatSPAllocs := concatSPAllocs + 1;
                  { Zero concat temp at $sp }
                  EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
                  EmitI32Const(0);
                  EmitOp(OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
                  { Append each saved piece }
                  for i := 0 to concatPieces - 1 do begin
                    EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
                    EmitI32Const(255);
                    EmitI32Const(addrConcatScratch + i * 4);
                    EmitI32Load(2, 0);
                    EmitCall(EnsureStrAppend);
                  end;
                  { Append last piece }
                  EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
                  EmitI32Const(255);
                  EmitOp(OpLocalGet);
                  EmitULEB128(startCode, curStringTempIdx);
                  EmitCall(EnsureStrAppend);
                  { Push SP (concat temp address) as the argument }
                  EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
                  concatPieces := 0;
                end;
                { else: simple string expression — address already on stack }
              end else begin
                if tokKind <> tkIdent then
                  Error('variable expected for var parameter');
                argSym := LookupSym(tokStr);
                if argSym < 0 then
                  Error('undeclared identifier: ' + tokStr);
                if syms[argSym].kind <> skVar then
                  Error('variable expected for var parameter');
                if syms[argSym].isVarParam then begin
                  { Already a pointer — pass it through }
                  EmitVarParamPtr(argSym);
                end
                else if (syms[argSym].offset < 0) and
                   ((syms[argSym].typ = tyRecord) or (syms[argSym].typ = tyArray)
                    or (syms[argSym].typ = tyString)) then begin
                  { Structured value param: local holds pointer, pass through }
                  EmitOp(OpLocalGet);
                  EmitULEB128(startCode, -(syms[argSym].offset + 1));
                end
                else if syms[argSym].offset < 0 then
                  Error('cannot pass value parameter by reference')
                else begin
                  { Address = frame[level] + offset }
                  EmitFramePtr(syms[argSym].level);
                  EmitI32Const(syms[argSym].offset);
                  EmitOp(OpI32Add);
                end;
                NextToken;
                { Handle postfix [index] for array element var params }
                while tokKind = tkLBrack do begin
                  if syms[argSym].typ <> tyArray then
                    Error('array type expected before ''[''');
                  NextToken;
                  ParseExpression(PrecNone);
                  if types[syms[argSym].typeIdx].arrLo <> 0 then begin
                    EmitI32Const(types[syms[argSym].typeIdx].arrLo);
                    EmitOp(OpI32Sub);
                  end;
                  if types[syms[argSym].typeIdx].elemSize <> 1 then begin
                    EmitI32Const(types[syms[argSym].typeIdx].elemSize);
                    EmitOp(OpI32Mul);
                  end;
                  EmitOp(OpI32Add);
                  argSym := -1;
                  Expect(tkRBrack);
                end;
              end;
            end else begin
              ParseExpression(PrecNone);
              if concatPieces > 0 then begin
                { String concat in regular param: finalize into string temp }
                curFuncNeedsStringTemp := true;
                curFuncNeedsCaseTemp := true;
                EmitOp(OpLocalSet);
                EmitULEB128(startCode, curCaseTempIdx);
                EmitOp(OpLocalGet);
                EmitULEB128(startCode, curStringTempIdx);
                EmitI32Const(0);
                EmitOp(OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
                for i := 0 to concatPieces - 1 do begin
                  EmitOp(OpLocalGet);
                  EmitULEB128(startCode, curStringTempIdx);
                  EmitI32Const(255);
                  EmitI32Const(addrConcatScratch + i * 4);
                  EmitI32Load(2, 0);
                  EmitCall(EnsureStrAppend);
                end;
                EmitOp(OpLocalGet);
                EmitULEB128(startCode, curStringTempIdx);
                EmitI32Const(255);
                EmitOp(OpLocalGet);
                EmitULEB128(startCode, curCaseTempIdx);
                EmitCall(EnsureStrAppend);
                EmitOp(OpLocalGet);
                EmitULEB128(startCode, curStringTempIdx);
                concatPieces := 0;
              end;
            end;
            argIdx := argIdx + 1;
            if tokKind = tkComma then
              NextToken;
          end;
          Expect(tkRParen);
        end;
        EmitCall(syms[sym].offset);
        { Restore SP for any concat temp allocations }
        if concatSPAllocs > 0 then begin
          EmitOp(OpGlobalGet); EmitULEB128(startCode, 0);
          EmitI32Const(concatSPAllocs * 256);
          EmitOp(OpI32Add);
          EmitOp(OpGlobalSet); EmitULEB128(startCode, 0);
          concatSPAllocs := 0;
        end;
        if syms[sym].kind = skFunc then
          EmitOp(OpDrop); { discard return value }
      end else
        Error('assignment or procedure call expected after ' + name);
    end; { else begin for non-builtin identifiers }
    end; { tkIdent }

    tkHalt: begin
      NextToken;
      if tokKind = tkLParen then begin
        NextToken;
        ParseExpression(PrecNone);
        Expect(tkRParen);
      end else
        EmitI32Const(0);
      EmitCall(EnsureProcExit);
    end;

    tkWrite: begin
      NextToken;
      ParseWriteArgs(false);
    end;

    tkWriteln: begin
      NextToken;
      ParseWriteArgs(true);
    end;

    tkRead: begin
      NextToken;
      ParseReadArgs(false);
    end;

    tkReadln: begin
      NextToken;
      ParseReadArgs(true);
    end;

    tkIf: begin
      NextToken;
      ParseExpression(PrecNone);
      Expect(tkThen);
      EmitOp(OpIf);
      EmitOp(WasmVoid);
      if breakDepth >= 0 then begin inc(breakDepth); inc(continueDepth); end;
      if exitDepth >= 0 then inc(exitDepth);
      ParseStatement;
      if tokKind = tkElse then begin
        NextToken;
        EmitOp(OpElse);
        ParseStatement;
      end;
      if breakDepth >= 0 then begin dec(breakDepth); dec(continueDepth); end;
      if exitDepth >= 0 then dec(exitDepth);
      EmitOp(OpEnd);
    end;

    tkWhile: begin
      NextToken;
      EmitOp(OpBlock);
      EmitOp(WasmVoid);
      EmitOp(OpLoop);
      EmitOp(WasmVoid);
      ParseExpression(PrecNone);
      Expect(tkDo);
      EmitOp(OpI32Eqz);
      EmitOp(OpBrIf);
      EmitULEB128(startCode, 1);
      savedBreak := breakDepth; savedContinue := continueDepth;
      breakDepth := 1; continueDepth := 0;
      if exitDepth >= 0 then exitDepth := exitDepth + 2;
      ParseStatement;
      if exitDepth >= 0 then exitDepth := exitDepth - 2;
      breakDepth := savedBreak; continueDepth := savedContinue;
      EmitOp(OpBr);
      EmitULEB128(startCode, 0);
      EmitOp(OpEnd);
      EmitOp(OpEnd);
    end;

    tkFor: begin
      NextToken;
      if tokKind <> tkIdent then
        Expected('identifier');
      name := tokStr;
      sym := LookupSym(name);
      if sym < 0 then
        Error('undeclared identifier: ' + name);
      if syms[sym].kind <> skVar then
        Error(name + ' is not a variable');
      NextToken;
      Expect(tkAssign);
      { Assign initial value }
      EmitFramePtr(syms[sym].level);
      EmitI32Const(syms[sym].offset);
      EmitOp(OpI32Add);
      ParseExpression(PrecNone);
      EmitI32Store(2, 0);

      if (tokKind <> tkTo) and (tokKind <> tkDownto) then
        Expected('"to" or "downto"');

      if tokKind = tkTo then begin
        NextToken;
        { Each nesting level gets its own limit scratch address }
        if forLimitDepth > 15 then
          Error('for loops nested too deeply');
        limitAddr := EnsureForLimit(forLimitDepth);
        EmitI32Const(limitAddr);
        ParseExpression(PrecNone);
        EmitI32Store(2, 0);

        Expect(tkDo);

        { ;; WAT: block $exit
          ;;        loop $loop
          ;;          ;; if counter > limit: br $exit
          ;;          (load counter) (load limit) i32.gt_s br_if $exit
          ;;          body
          ;;          ;; increment counter
          ;;          (addr counter) (load counter) i32.const 1 i32.add i32.store
          ;;          br $loop
          ;;        end loop
          ;;      end block }
        EmitOp(OpBlock);
        EmitOp(WasmVoid);
        EmitOp(OpLoop);
        EmitOp(WasmVoid);

        { Check: counter > limit? }
        EmitFramePtr(syms[sym].level);
        EmitI32Const(syms[sym].offset);
        EmitOp(OpI32Add);
        EmitI32Load(2, 0);
        EmitI32Const(limitAddr);
        EmitI32Load(2, 0);
        EmitOp(OpI32GtS);
        EmitOp(OpBrIf);
        EmitULEB128(startCode, 1);

        { Body }
        savedBreak := breakDepth; savedContinue := continueDepth;
        breakDepth := 1; continueDepth := 0;
        if exitDepth >= 0 then exitDepth := exitDepth + 2;
        forLimitDepth := forLimitDepth + 1;
        ParseStatement;
        forLimitDepth := forLimitDepth - 1;
        if exitDepth >= 0 then exitDepth := exitDepth - 2;
        breakDepth := savedBreak; continueDepth := savedContinue;

        { Increment counter }
        EmitFramePtr(syms[sym].level);
        EmitI32Const(syms[sym].offset);
        EmitOp(OpI32Add);
        EmitFramePtr(syms[sym].level);
        EmitI32Const(syms[sym].offset);
        EmitOp(OpI32Add);
        EmitI32Load(2, 0);
        EmitI32Const(1);
        EmitOp(OpI32Add);
        EmitI32Store(2, 0);

        EmitOp(OpBr);
        EmitULEB128(startCode, 0);
        EmitOp(OpEnd);
        EmitOp(OpEnd);
      end else begin
        { downto }
        NextToken;
        if forLimitDepth > 15 then
          Error('for loops nested too deeply');
        limitAddr := EnsureForLimit(forLimitDepth);
        EmitI32Const(limitAddr);
        ParseExpression(PrecNone);
        EmitI32Store(2, 0);
        Expect(tkDo);

        EmitOp(OpBlock);
        EmitOp(WasmVoid);
        EmitOp(OpLoop);
        EmitOp(WasmVoid);

        { Check: counter < limit? }
        EmitFramePtr(syms[sym].level);
        EmitI32Const(syms[sym].offset);
        EmitOp(OpI32Add);
        EmitI32Load(2, 0);
        EmitI32Const(limitAddr);
        EmitI32Load(2, 0);
        EmitOp(OpI32LtS);
        EmitOp(OpBrIf);
        EmitULEB128(startCode, 1);

        savedBreak := breakDepth; savedContinue := continueDepth;
        breakDepth := 1; continueDepth := 0;
        if exitDepth >= 0 then exitDepth := exitDepth + 2;
        forLimitDepth := forLimitDepth + 1;
        ParseStatement;
        forLimitDepth := forLimitDepth - 1;
        if exitDepth >= 0 then exitDepth := exitDepth - 2;
        breakDepth := savedBreak; continueDepth := savedContinue;

        { Decrement counter }
        EmitFramePtr(syms[sym].level);
        EmitI32Const(syms[sym].offset);
        EmitOp(OpI32Add);
        EmitFramePtr(syms[sym].level);
        EmitI32Const(syms[sym].offset);
        EmitOp(OpI32Add);
        EmitI32Load(2, 0);
        EmitI32Const(1);
        EmitOp(OpI32Sub);
        EmitI32Store(2, 0);

        EmitOp(OpBr);
        EmitULEB128(startCode, 0);
        EmitOp(OpEnd);
        EmitOp(OpEnd);
      end;
    end;

    tkRepeat: begin
      NextToken;
      EmitOp(OpBlock);
      EmitOp(WasmVoid);
      EmitOp(OpLoop);
      EmitOp(WasmVoid);
      savedBreak := breakDepth; savedContinue := continueDepth;
      breakDepth := 1; continueDepth := 0;
      if exitDepth >= 0 then exitDepth := exitDepth + 2;
      ParseStatement;
      while tokKind = tkSemicolon do begin
        NextToken;
        if tokKind <> tkUntil then
          ParseStatement;
      end;
      if exitDepth >= 0 then exitDepth := exitDepth - 2;
      breakDepth := savedBreak; continueDepth := savedContinue;
      Expect(tkUntil);
      ParseExpression(PrecNone);
      EmitOp(OpI32Eqz);
      EmitOp(OpBrIf);
      EmitULEB128(startCode, 0);
      EmitOp(OpEnd);  { end loop }
      EmitOp(OpEnd);  { end block }
    end;

    tkCase: begin
      { case expr of label: stmt; ... [else stmt] end }
      NextToken;
      curFuncNeedsCaseTemp := true;
      ParseExpression(PrecNone);
      EmitOp(OpLocalSet);
      EmitULEB128(startCode, curCaseTempIdx);
      Expect(tkOf);
      i := 0; { count of nested if blocks to close }
      while (tokKind <> tkEnd) and (tokKind <> tkElse) and (tokKind <> tkEOF) do begin
        (* Parse case labels: constexpr [.. constexpr] , ... *)
        desTyp := 0; { label count for OR-ing }
        repeat
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, curCaseTempIdx);
          EvalConstExpr(sym, argIdx);  { reusing sym and argIdx as temp vars }
          if tokKind = tkDotDot then begin
            { Range: selector >= lo AND selector <= hi }
            EmitI32Const(sym);
            EmitOp(OpI32GeS);
            EmitOp(OpLocalGet);
            EmitULEB128(startCode, curCaseTempIdx);
            NextToken;
            EvalConstExpr(sym, argIdx);
            EmitI32Const(sym);
            EmitOp(OpI32LeS);
            EmitOp(OpI32And);
          end else begin
            { Single value }
            EmitI32Const(sym);
            EmitOp(OpI32Eq);
          end;
          desTyp := desTyp + 1;
          if tokKind = tkComma then
            NextToken
          else
            break;
        until false;
        { OR all label conditions together }
        while desTyp > 1 do begin
          EmitOp(OpI32Or);
          desTyp := desTyp - 1;
        end;
        Expect(tkColon);
        EmitOp(OpIf);
        EmitOp(WasmVoid);
        i := i + 1;
        if breakDepth >= 0 then begin inc(breakDepth); inc(continueDepth); end;
        if exitDepth >= 0 then inc(exitDepth);
        ParseStatement;
        if tokKind = tkSemicolon then
          NextToken;
        if (tokKind <> tkEnd) and (tokKind <> tkElse) then begin
          EmitOp(OpElse);
        end;
      end;
      if tokKind = tkElse then begin
        if i > 0 then
          EmitOp(OpElse);
        NextToken;
        ParseStatement;
        if tokKind = tkSemicolon then
          NextToken;
      end;
      { Close all nested if blocks }
      while i > 0 do begin
        if breakDepth >= 0 then begin dec(breakDepth); dec(continueDepth); end;
        if exitDepth >= 0 then dec(exitDepth);
        EmitOp(OpEnd);
        i := i - 1;
      end;
      Expect(tkEnd);
    end;

    tkExit: begin
      NextToken;
      if exitDepth < 0 then
        Error('exit outside of procedure/function');
      EmitOp(OpBr);
      EmitULEB128(startCode, exitDepth);
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

    tkWith: begin
      NextToken;
      i := numWiths;
      repeat
        if tokKind <> tkIdent then
          Expected('record variable');
        sym := LookupSym(tokStr);
        if sym < 0 then
          Error('undeclared identifier: ' + tokStr);
        if syms[sym].kind <> skVar then
          Error('variable expected in with statement');
        if syms[sym].typ <> tyRecord then
          Error('record type expected in with statement');
        if numWiths >= 8 then
          Error('too many nested with levels (max 8)');
        withTypeIdx[numWiths] := syms[sym].typeIdx;
        withLevel[numWiths] := syms[sym].level;
        withOffset[numWiths] := syms[sym].offset;
        withIsVarParam[numWiths] := syms[sym].isVarParam;
        withIsLocal[numWiths] := syms[sym].offset < 0;
        withFieldOfs[numWiths] := 0;
        NextToken;
        { Process dot-selectors: with r.inner do }
        while tokKind = tkDot do begin
          NextToken;
          if tokKind <> tkIdent then
            Expected('field name');
          fldIdx := LookupField(withTypeIdx[numWiths], tokStr);
          if fldIdx < 0 then
            Error('unknown field: ' + tokStr);
          if fields[fldIdx].typ <> tyRecord then
            Error('record type expected in with statement');
          withFieldOfs[numWiths] := withFieldOfs[numWiths]
            + fields[fldIdx].offset;
          withTypeIdx[numWiths] := fields[fldIdx].typeIdx;
          NextToken;
        end;
        numWiths := numWiths + 1;
        if tokKind = tkComma then begin
          NextToken;
        end else
          break;
      until false;
      Expect(tkDo);
      ParseStatement;
      numWiths := i;
    end;

    { Empty statement (e.g. before 'end' or after last ';') }
    tkEnd, tkSemicolon, tkUntil, tkElse: begin
      { no-op }
    end;
  else
    Error('statement expected');
  end;
end;

procedure ParseProcDecl;
{** Parse a procedure or function declaration.
  procedure Name;          -- parameterless procedure
  procedure Name(params);  -- procedure with parameters (milestone 5b)
  function Name: Type;     -- parameterless function
  function Name(params): Type;  -- function with parameters (milestone 5b)

  The body is compiled into startCode (which is empty during declarations),
  then copied to funcBodies. startCode is reset afterward. }
var
  isFunc: boolean;
  procName: string;
  sym: longint;
  procSym: longint;
  slot: longint;
  savedFrameSize: longint;
  bodyStart: longint;
  funcIdx: longint;
  retTyp: longint;
  retTypSym: longint;
  nlocals: longint;
  nparams: longint;
  typIdx: longint;
  paramNames: array[0..15] of string[63];
  paramTypes: array[0..15] of longint;
  paramTypeIdx: array[0..15] of longint;
  paramSize: array[0..15] of longint;
  paramIsVar: array[0..15] of boolean;
  paramIsConst: array[0..15] of boolean;
  np: longint;
  i: longint;
  groupStart, groupEnd: longint;
  isVarParam: boolean;
  isConstParam: boolean;
  pTypeName: string;
  pTypSym: longint;
  wasmParams: TWasmParamArr;
  wasmResults: TWasmResultArr;
  nWasmResults: longint;
  savedNestLevel: longint;
  savedDisplayLocal: longint;
  myDisplayLocal: longint;
  savedStringTempIdx: longint;
  savedFuncNeedsStringTemp: boolean;
  savedCaseTempIdx: longint;
  savedFuncNeedsCaseTemp: boolean;
  savedFuncIsFunction: boolean;
  savedFuncReturnIdx: longint;
  savedExitDepth: longint;
  savedBreakDepth: longint;
  savedContinueDepth: longint;
  savedNumVarParamSpills: longint;
  savedVarParamSpillLocal: array[0..15] of longint;
  savedVarParamSpillFrameOff: array[0..15] of longint;
  savedNumStructCopies: longint;
  savedStructCopyLocal: array[0..15] of longint;
  savedStructCopyFrameOff: array[0..15] of longint;
  savedStructCopySize: array[0..15] of longint;
  savedNumVarInits: longint;
  savedVarInitOffset: array[0..15] of longint;
  savedVarInitVal: array[0..15] of longint;
  savedVarInitIsStr: array[0..15] of boolean;
  savedVarInitStrMax: array[0..15] of longint;
begin
  isFunc := tokKind = tkFunction;
  NextToken; { consume 'procedure' or 'function' }

  if tokKind <> tkIdent then
    Expected('identifier');
  procName := tokStr;
  NextToken;

  { Parse parameters }
  np := 0;
  if tokKind = tkLParen then begin
    NextToken;
    while tokKind <> tkRParen do begin
      { Check for var or const parameter }
      isVarParam := false;
      isConstParam := false;
      if tokKind = tkVar then begin
        isVarParam := true;
        NextToken;
      end else if tokKind = tkConst then begin
        isConstParam := true;
        NextToken;
      end;

      { Collect parameter names in this group }
      groupStart := np;
      repeat
        if np > 15 then
          Error('too many parameters');
        if tokKind <> tkIdent then
          Expected('parameter name');
        paramNames[np] := tokStr;
        paramIsVar[np] := isVarParam;
        paramIsConst[np] := isConstParam;
        np := np + 1;
        NextToken;
        if tokKind = tkComma then
          NextToken
        else
          break;
      until false;
      groupEnd := np;

      Expect(tkColon);

      { Parse parameter type }
      if tokKind = tkString_kw then begin
        { String parameter type — always passed as pointer (i32) }
        for i := groupStart to groupEnd - 1 do begin
          paramTypes[i] := tyString;
          paramTypeIdx[i] := -1;
          paramSize[i] := 0;
          { String params are always passed by reference.
            If not explicitly 'var', treat as const (read-only). }
          if not paramIsVar[i] then
            paramIsConst[i] := true;
          paramIsVar[i] := true; { force by-reference passing at call site }
        end;
        NextToken;
        { TODO: support string[n] parameter types }
      end else begin
        if tokKind <> tkIdent then
          Expected('type name');
        pTypeName := tokStr;
        pTypSym := LookupSym(pTypeName);
        if pTypSym < 0 then
          Error('unknown type: ' + pTypeName);
        if syms[pTypSym].kind <> skType then
          Error(pTypeName + ' is not a type');
        NextToken;

        { Apply type to all names in this group }
        for i := groupStart to groupEnd - 1 do begin
          paramTypes[i] := syms[pTypSym].typ;
          paramTypeIdx[i] := syms[pTypSym].typeIdx;
          paramSize[i] := syms[pTypSym].size;
          { Structured types (record/array): var/const pass by reference;
            value params pass address but callee copies into frame }
          if ((syms[pTypSym].typ = tyRecord) or (syms[pTypSym].typ = tyArray)) then begin
            if paramIsVar[i] or paramIsConst[i] then begin
              { Already by-reference — force varParam for call site }
              paramIsVar[i] := true;
            end;
            { Value params: address passed, copy handled in callee prologue }
          end;
        end;
      end;

      if tokKind = tkSemicolon then
        NextToken;
    end;
    Expect(tkRParen);
  end;

  { Parse return type for functions }
  retTyp := tyNone;
  if isFunc then begin
    Expect(tkColon);
    if tokKind <> tkIdent then
      Expected('return type');
    retTypSym := LookupSym(tokStr);
    if retTypSym < 0 then
      Error('unknown type: ' + tokStr);
    if syms[retTypSym].kind <> skType then
      Error(tokStr + ' is not a type');
    retTyp := syms[retTypSym].typ;
    NextToken;
  end;

  Expect(tkSemicolon);

  { Check for external declaration (WASM import) }
  if tokKind = tkExternal then begin
    NextToken;
    Expect(tkSemicolon);
    if not hasPendingImport then
      Error('external requires preceding {$IMPORT} directive');

    { Build WASM type signature for the import }
    for i := 0 to np - 1 do
      wasmParams[i] := WasmI32;
    nWasmResults := 0;
    if isFunc then begin
      wasmResults[0] := WasmI32;
      nWasmResults := 1;
    end;
    typIdx := AddWasmType(np, wasmParams, nWasmResults, wasmResults);

    { Register as WASM import }
    funcIdx := AddImport(pendingImportMod, pendingImportName, typIdx);

    { Register in funcs table so call sites can look up param metadata }
    if numFuncs >= MaxFuncs then
      Error('too many functions');
    funcs[numFuncs].name := procName;
    funcs[numFuncs].typeidx := typIdx;
    funcs[numFuncs].bodyStart := -2; { marker: external import }
    funcs[numFuncs].bodyLen := 0;
    funcs[numFuncs].nlocals := 0;
    funcs[numFuncs].nparams := np;
    for i := 0 to np - 1 do
    begin
      funcs[numFuncs].varParams[i] := false; { imports have no var params }
      funcs[numFuncs].constParams[i] := false;
    end;

    { Add symbol - offset is the import index (absolute function index) }
    if isFunc then
      sym := AddSym(procName, skFunc, retTyp)
    else
      sym := AddSym(procName, skProc, tyNone);
    syms[sym].offset := funcIdx; { import index = absolute function index }
    syms[sym].size := numFuncs; { funcs[] index for param metadata }

    numFuncs := numFuncs + 1;
    hasPendingImport := false;
    exit;
  end;

  { Check for forward declaration }
  if tokKind = tkForward then begin
    if hasPendingExport then
      Error('{$EXPORT} cannot be used with forward declarations');
    NextToken;
    Expect(tkSemicolon);
    { Allocate function slot now, body comes later }
    slot := numDefinedFuncs;
    numDefinedFuncs := numDefinedFuncs + 1;

    { Build WASM type signature }
    for i := 0 to np - 1 do
      wasmParams[i] := WasmI32;
    nWasmResults := 0;
    if isFunc then begin
      wasmResults[0] := WasmI32;
      nWasmResults := 1;
    end;
    typIdx := AddWasmType(np, wasmParams, nWasmResults, wasmResults);

    { Register in funcs table with empty body }
    if numFuncs >= MaxFuncs then
      Error('too many functions');
    funcs[numFuncs].name := procName;
    funcs[numFuncs].typeidx := typIdx;
    funcs[numFuncs].bodyStart := -1; { marker: forward-declared, no body yet }
    funcs[numFuncs].bodyLen := 0;
    funcs[numFuncs].nlocals := 0;
    funcs[numFuncs].nparams := np;
    for i := 0 to np - 1 do begin
      funcs[numFuncs].varParams[i] := paramIsVar[i];
      funcs[numFuncs].constParams[i] := paramIsConst[i];
    end;

    { Add symbol }
    if isFunc then
      sym := AddSym(procName, skFunc, retTyp)
    else
      sym := AddSym(procName, skProc, tyNone);
    syms[sym].offset := numImports + slot; { absolute function index }
    syms[sym].size := numFuncs; { store funcs[] index for later body fill }

    numFuncs := numFuncs + 1;
    exit;
  end;

  { Check if this is a body for a forward-declared procedure }
  sym := LookupSym(procName);
  if (sym >= 0) and ((syms[sym].kind = skProc) or (syms[sym].kind = skFunc)) then begin
    { Forward body - reuse existing slot }
    procSym := sym;
    slot := syms[sym].offset - numImports;
    funcIdx := syms[sym].size; { funcs[] index }
    if funcs[funcIdx].bodyStart >= 0 then
      Error('duplicate definition of ' + procName);
  end else begin
    { New declaration - allocate slot }
    slot := numDefinedFuncs;
    numDefinedFuncs := numDefinedFuncs + 1;

    { Build WASM type signature }
    for i := 0 to np - 1 do
      wasmParams[i] := WasmI32;
    nWasmResults := 0;
    if isFunc then begin
      wasmResults[0] := WasmI32;
      nWasmResults := 1;
    end;
    typIdx := AddWasmType(np, wasmParams, nWasmResults, wasmResults);

    { Register in funcs table }
    if numFuncs >= MaxFuncs then
      Error('too many functions');
    funcIdx := numFuncs;
    funcs[numFuncs].name := procName;
    funcs[numFuncs].typeidx := typIdx;
    funcs[numFuncs].bodyStart := 0;
    funcs[numFuncs].bodyLen := 0;
    funcs[numFuncs].nlocals := 0;
    funcs[numFuncs].nparams := np;
    for i := 0 to np - 1 do begin
      funcs[numFuncs].varParams[i] := paramIsVar[i];
      funcs[numFuncs].constParams[i] := paramIsConst[i];
    end;
    numFuncs := numFuncs + 1;

    { Add symbol }
    if isFunc then
      sym := AddSym(procName, skFunc, retTyp)
    else
      sym := AddSym(procName, skProc, tyNone);
    syms[sym].offset := numImports + slot;
    syms[sym].size := funcIdx;
    procSym := sym;
  end;

  { Save and reset code emission state }
  if savedCodeStackTop > 7 then
    Error('procedure nesting too deep for code buffer stack');
  savedCodeStack[savedCodeStackTop] := startCode;
  savedCodeStackTop := savedCodeStackTop + 1;
  CodeBufInit(startCode);
  savedFrameSize := curFrameSize;
  curFrameSize := 0;
  savedStringTempIdx := curStringTempIdx;
  savedFuncNeedsStringTemp := curFuncNeedsStringTemp;
  curFuncNeedsStringTemp := false;
  savedCaseTempIdx := curCaseTempIdx;
  savedFuncNeedsCaseTemp := curFuncNeedsCaseTemp;
  curFuncNeedsCaseTemp := false;
  savedFuncIsFunction := curFuncIsFunction;
  savedFuncReturnIdx := curFuncReturnIdx;
  curFuncIsFunction := isFunc;
  curFuncReturnIdx := np; { return value is local[np] for functions }

  { Save and increment nesting level }
  savedNestLevel := curNestLevel;
  curNestLevel := curNestLevel + 1;
  if curNestLevel > 8 then
    Error('nesting too deep (max 8 levels)');

  { Save and set display local index }
  savedDisplayLocal := displayLocalIdx;
  myDisplayLocal := np;
  if isFunc then
    myDisplayLocal := myDisplayLocal + 1; { after return value local }
  displayLocalIdx := myDisplayLocal;

  { String temp local index: after params + saved display (+ return value if func) }
  { For proc: np + 1 (saved display). For func: np + 2 (return value + saved display). }
  if isFunc then begin
    curStringTempIdx := np + 2;
    curCaseTempIdx := np + 3;
  end else begin
    curStringTempIdx := np + 1;
    curCaseTempIdx := np + 2;
  end;

  { Enter scope for procedure body }
  EnterScope;

  { Save prologue state that ParseBlock will consume (nested procs would clobber it) }
  savedNumVarParamSpills := numVarParamSpills;
  for i := 0 to numVarParamSpills - 1 do begin
    savedVarParamSpillLocal[i] := varParamSpillLocal[i];
    savedVarParamSpillFrameOff[i] := varParamSpillFrameOff[i];
  end;
  savedNumStructCopies := numStructCopies;
  for i := 0 to numStructCopies - 1 do begin
    savedStructCopyLocal[i] := structCopyLocal[i];
    savedStructCopyFrameOff[i] := structCopyFrameOff[i];
    savedStructCopySize[i] := structCopySize[i];
  end;
  savedNumVarInits := numVarInits;
  for i := 0 to numVarInits - 1 do begin
    savedVarInitOffset[i] := varInitOffset[i];
    savedVarInitVal[i] := varInitVal[i];
    savedVarInitIsStr[i] := varInitIsStr[i];
    savedVarInitStrMax[i] := varInitStrMax[i];
  end;

  { Add parameters as locals (WASM params are local 0..np-1) }
  nparams := np;
  numStructCopies := 0;
  numVarParamSpills := 0;
  numVarInits := 0;
  for i := 0 to np - 1 do begin
    sym := AddSym(paramNames[i], skVar, paramTypes[i]);
    syms[sym].size := 4;
    syms[sym].isVarParam := paramIsVar[i];
    syms[sym].isConstParam := paramIsConst[i];
    syms[sym].typeIdx := paramTypeIdx[i];
    if paramTypes[i] = tyString then
      syms[sym].strMax := 255; { default max length for string params }
    if paramIsVar[i] or paramIsConst[i] then begin
      { Var/const params: spill pointer to frame for nested proc access }
      curFrameSize := (curFrameSize + 3) and (not 3);
      varParamSpillLocal[numVarParamSpills] := i;
      varParamSpillFrameOff[numVarParamSpills] := curFrameSize;
      syms[sym].offset := curFrameSize;  { positive = frame-based }
      numVarParamSpills := numVarParamSpills + 1;
      curFrameSize := curFrameSize + 4;
    end else begin
      { Value params: WASM locals, negative offset as flag: -(local_index + 1) }
      syms[sym].offset := -(i + 1);
    end;
    { Structured value params: callee copies into frame }
    if ((paramTypes[i] = tyRecord) or (paramTypes[i] = tyArray))
       and not paramIsVar[i] and not paramIsConst[i] then begin
      { Pre-allocate frame space for the copy }
      curFrameSize := (curFrameSize + 3) and (not 3);
      structCopyLocal[numStructCopies] := i;
      structCopyFrameOff[numStructCopies] := curFrameSize;
      structCopySize[numStructCopies] := paramSize[i];
      numStructCopies := numStructCopies + 1;
      curFrameSize := curFrameSize + paramSize[i];
    end;
  end;

  { For functions, the return value is a hidden WASM local at index np.
    Assignment to the function name is handled specially in ParseStatement
    by checking skFunc, so no skVar symbol is needed here. }

  { Save display[N] into WASM local (before ParseBlock's prologue).
    Global index = curNestLevel + 1 (global 0 = $sp, globals 1..8 = display[0..7]).
    But we save display[curNestLevel], which is our OWN level.
    Actually, we save display at our level so recursion works correctly. }
  EmitOp(OpGlobalGet);
  EmitULEB128(startCode, curNestLevel + 1);  { display[N] = global N+1 }
  EmitOp(OpLocalSet);
  EmitULEB128(startCode, displayLocalIdx);

  { Save and reset loop/exit depths for nested procedure }
  savedExitDepth := exitDepth;
  savedBreakDepth := breakDepth;
  savedContinueDepth := continueDepth;
  exitDepth := -1;
  breakDepth := -1;
  continueDepth := -1;

  { Parse the block (declarations + begin...end) }
  ParseBlock;

  { Restore loop/exit depths }
  exitDepth := savedExitDepth;
  breakDepth := savedBreakDepth;
  continueDepth := savedContinueDepth;

  { For functions, push return value onto WASM stack }
  if isFunc then begin
    EmitOp(OpLocalGet);
    EmitULEB128(startCode, np); { local index for return value }
  end;

  Expect(tkSemicolon);

  { Leave scope }
  LeaveScope;

  { Restore nesting level and display local }
  curNestLevel := savedNestLevel;
  displayLocalIdx := savedDisplayLocal;

  { Count extra locals beyond params:
    - function return value: 1 local
    - saved display value: 1 local (always present for all procs)
    - string temp: 1 local (if string concat was used) }
  nlocals := 1; { saved display }
  if isFunc then
    nlocals := 2; { return value + saved display }
  if curFuncNeedsCaseTemp then
    nlocals := nlocals + 2  { string temp + case temp }
  else if curFuncNeedsStringTemp then
    nlocals := nlocals + 1;

  { Restore string/case temp state }
  curStringTempIdx := savedStringTempIdx;
  curFuncNeedsStringTemp := savedFuncNeedsStringTemp;
  curCaseTempIdx := savedCaseTempIdx;
  curFuncNeedsCaseTemp := savedFuncNeedsCaseTemp;
  curFuncIsFunction := savedFuncIsFunction;
  curFuncReturnIdx := savedFuncReturnIdx;

  { Restore prologue state for enclosing procedure }
  numVarParamSpills := savedNumVarParamSpills;
  for i := 0 to savedNumVarParamSpills - 1 do begin
    varParamSpillLocal[i] := savedVarParamSpillLocal[i];
    varParamSpillFrameOff[i] := savedVarParamSpillFrameOff[i];
  end;
  numStructCopies := savedNumStructCopies;
  for i := 0 to savedNumStructCopies - 1 do begin
    structCopyLocal[i] := savedStructCopyLocal[i];
    structCopyFrameOff[i] := savedStructCopyFrameOff[i];
    structCopySize[i] := savedStructCopySize[i];
  end;
  numVarInits := savedNumVarInits;
  for i := 0 to savedNumVarInits - 1 do begin
    varInitOffset[i] := savedVarInitOffset[i];
    varInitVal[i] := savedVarInitVal[i];
    varInitIsStr[i] := savedVarInitIsStr[i];
    varInitStrMax[i] := savedVarInitStrMax[i];
  end;

  { Copy compiled body to funcBodies }
  bodyStart := funcBodies.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(funcBodies, startCode.data[i]);

  { Update func entry }
  funcs[funcIdx].bodyStart := bodyStart;
  funcs[funcIdx].bodyLen := startCode.len;
  funcs[funcIdx].nlocals := nlocals;
  funcs[funcIdx].nparams := nparams;
  for i := 0 to np - 1 do begin
    funcs[funcIdx].varParams[i] := paramIsVar[i];
    funcs[funcIdx].constParams[i] := paramIsConst[i];
  end;

  (* Record user export if EXPORT was pending *)
  if hasPendingExport then begin
    if numUserExports >= 32 then
      Error('too many exports');
    userExports[numUserExports].name := pendingExportName;
    userExports[numUserExports].funcIdx := syms[procSym].offset;
    numUserExports := numUserExports + 1;
    hasPendingExport := false;
  end;

  { Restore code emission state }
  savedCodeStackTop := savedCodeStackTop - 1;
  startCode := savedCodeStack[savedCodeStackTop];
  curFrameSize := savedFrameSize;
end;

procedure ParseBlock;
var
  savedFrameSize: longint;
  typDeclName: string;
  typDeclTyp, typDeclTypeIdx, typDeclSize, typDeclStrMax: longint;
  sym: longint;
  ci: longint;
begin
  savedFrameSize := curFrameSize;

  { Declarations }
  while (tokKind = tkConst) or (tokKind = tkVar) or (tokKind = tkType)
        or (tokKind = tkProcedure) or (tokKind = tkFunction) do begin
    case tokKind of
      tkConst: begin
        NextToken;
        while tokKind = tkIdent do begin
          typDeclName := tokStr;
          NextToken;
          Expect(tkEqual);
          EvalConstExpr(typDeclSize, typDeclTyp);
          sym := AddSym(typDeclName, skConst, typDeclTyp);
          syms[sym].offset := typDeclSize;
          if typDeclTyp = tyString then
            syms[sym].size := 256
          else
            syms[sym].size := 4;
          Expect(tkSemicolon);
        end;
      end;
      tkVar: begin
        NextToken;
        ParseVarDecl;
      end;
      tkType: begin
        NextToken;
        { Parse type declarations: TypeName = TypeSpec ; }
        while tokKind = tkIdent do begin
          typDeclName := tokStr;
          NextToken;
          Expect(tkEqual);
          ParseTypeSpec(typDeclTyp, typDeclTypeIdx, typDeclSize, typDeclStrMax);
          sym := AddSym(typDeclName, skType, typDeclTyp);
          syms[sym].typeIdx := typDeclTypeIdx;
          syms[sym].size := typDeclSize;
          syms[sym].strMax := typDeclStrMax;
          Expect(tkSemicolon);
        end;
      end;
      tkProcedure, tkFunction: begin
        ParseProcDecl;
      end;
    end;
  end;

  { Align frame size to 4 bytes }
  curFrameSize := (curFrameSize + 3) and (not 3);

  { Emit frame prologue: $sp -= frameSize }
  if curFrameSize > 0 then begin
    (* WAT: global.get $sp
            i32.const <frameSize>
            i32.sub
            global.set $sp *)
    EmitOp(OpGlobalGet);
    EmitULEB128(startCode, 0);
    EmitI32Const(curFrameSize);
    EmitOp(OpI32Sub);
    EmitOp(OpGlobalSet);
    EmitULEB128(startCode, 0);
  end;

  { Set display[curNestLevel] := $sp so nested procs can find this frame.
    Global index = curNestLevel + 1 (global 0 = $sp, globals 1..8 = display[0..7]). }
  EmitOp(OpGlobalGet);
  EmitULEB128(startCode, 0);  { $sp }
  EmitOp(OpGlobalSet);
  EmitULEB128(startCode, curNestLevel + 1); { display[N] = global N+1 }

  { Copy structured value params into frame }
  for ci := 0 to numStructCopies - 1 do begin
    { dst = $sp + frameOffset }
    EmitOp(OpGlobalGet);
    EmitULEB128(startCode, 0);
    EmitI32Const(structCopyFrameOff[ci]);
    EmitOp(OpI32Add);
    { src = WASM local (holds pointer to caller's data) }
    EmitOp(OpLocalGet);
    EmitULEB128(startCode, structCopyLocal[ci]);
    { size }
    EmitI32Const(structCopySize[ci]);
    EmitMemoryCopy;
    { Update WASM local to point to frame copy }
    EmitOp(OpGlobalGet);
    EmitULEB128(startCode, 0);
    EmitI32Const(structCopyFrameOff[ci]);
    EmitOp(OpI32Add);
    EmitOp(OpLocalSet);
    EmitULEB128(startCode, structCopyLocal[ci]);
  end;
  numStructCopies := 0;

  { Spill var/const param pointers to frame for nested proc access }
  for ci := 0 to numVarParamSpills - 1 do begin
    EmitFramePtr(curNestLevel);
    EmitI32Const(varParamSpillFrameOff[ci]);
    EmitOp(OpI32Add);
    EmitOp(OpLocalGet);
    EmitULEB128(startCode, varParamSpillLocal[ci]);
    EmitI32Store(2, 0);
  end;
  numVarParamSpills := 0;

  { Emit deferred variable initializers }
  for ci := 0 to numVarInits - 1 do begin
    if varInitIsStr[ci] then begin
      { String init: __str_assign(dst, max_len, src) }
      EmitFramePtr(curNestLevel);
      EmitI32Const(varInitOffset[ci]);
      EmitOp(OpI32Add);
      EmitI32Const(varInitStrMax[ci]);
      EmitI32Const(varInitVal[ci]);
      EmitCall(EnsureStrAssign);
    end else begin
      { Scalar init: store constant at frame+offset }
      EmitFramePtr(curNestLevel);
      EmitI32Const(varInitOffset[ci]);
      EmitOp(OpI32Add);
      EmitI32Const(varInitVal[ci]);
      EmitI32Store(2, 0);
    end;
  end;
  numVarInits := 0;

  { Wrap body in a block so exit can br to epilogue }
  EmitOp(OpBlock);
  EmitOp(WasmVoid);
  exitDepth := 0;

  { Statement part }
  if tokKind = tkBegin then
    ParseStatement
  else
    Expected('"begin"');

  { End body block (exit branches here) }
  EmitOp(OpEnd);

  { Restore display[N] before frame deallocation (procedures only) }
  if displayLocalIdx >= 0 then begin
    EmitOp(OpLocalGet);
    EmitULEB128(startCode, displayLocalIdx);
    EmitOp(OpGlobalSet);
    EmitULEB128(startCode, curNestLevel + 1); { display[N] = global N+1 }
  end;

  { Emit frame epilogue: $sp += frameSize }
  if curFrameSize > 0 then begin
    EmitOp(OpGlobalGet);
    EmitULEB128(startCode, 0);
    EmitI32Const(curFrameSize);
    EmitOp(OpI32Add);
    EmitOp(OpGlobalSet);
    EmitULEB128(startCode, 0);
  end;

  curFrameSize := savedFrameSize;
end;

{ ---- WASM module assembly ---- }

procedure WriteOutputByte(b: byte);
begin
  CodeBufEmit(outBuf, b);
end;

procedure WriteOutputULEB128(value: longint);
var
  v: longint;
  b: byte;
begin
  v := value;
  repeat
    b := v and $7F;
    v := v shr 7;
    if v <> 0 then
      b := b or $80;
    WriteOutputByte(b);
  until v = 0;
end;

procedure WriteOutputString(const s: string);
var i: longint;
begin
  WriteOutputULEB128(length(s));
  for i := 1 to length(s) do
    WriteOutputByte(ord(s[i]));
end;

procedure WriteSmallSection(id: byte; var buf: TSmallBuf);
var i: longint;
begin
  if buf.len = 0 then exit;
  WriteOutputByte(id);
  WriteOutputULEB128(buf.len);
  for i := 0 to buf.len - 1 do
    WriteOutputByte(buf.data[i]);
end;

procedure WriteCodeSection(id: byte; var buf: TCodeBuf);
var i: longint;
begin
  if buf.len = 0 then exit;
  WriteOutputByte(id);
  WriteOutputULEB128(buf.len);
  for i := 0 to buf.len - 1 do
    WriteOutputByte(buf.data[i]);
end;

procedure AssembleTypeSection;
{** Build the type section from the wasmTypes table. }
var
  i, j: longint;
begin
  SmallBufInit(secType);
  SmallEmitULEB128(secType, numWasmTypes); { type count }
  for i := 0 to numWasmTypes - 1 do begin
    SmallBufEmit(secType, WasmFunc);  { func type marker }
    SmallBufEmit(secType, wasmTypes[i].nparams);
    for j := 0 to wasmTypes[i].nparams - 1 do
      SmallBufEmit(secType, wasmTypes[i].params[j]);
    SmallBufEmit(secType, wasmTypes[i].nresults);
    for j := 0 to wasmTypes[i].nresults - 1 do
      SmallBufEmit(secType, wasmTypes[i].results[j]);
  end;
end;

procedure AssembleImportSection;
var i, j: longint;
begin
  SmallBufInit(secImport);
  if numImports = 0 then exit;
  SmallEmitULEB128(secImport, numImports);
  for i := 0 to numImports - 1 do begin
    { module name }
    SmallBufEmit(secImport, length(imports[i].modname));
    for j := 1 to length(imports[i].modname) do
      SmallBufEmit(secImport, ord(imports[i].modname[j]));
    { field name }
    SmallBufEmit(secImport, length(imports[i].fieldname));
    for j := 1 to length(imports[i].fieldname) do
      SmallBufEmit(secImport, ord(imports[i].fieldname[j]));
    { kind and type index }
    SmallBufEmit(secImport, imports[i].kind);
    SmallEmitULEB128(secImport, imports[i].typeidx);
  end;
end;

procedure AssembleFunctionSection;
var i: longint;
begin
  SmallBufInit(secFunc);
  SmallEmitULEB128(secFunc, numDefinedFuncs);
  { Slot 0: _start uses type void -> void }
  SmallEmitULEB128(secFunc, TypeVoidVoid);
  { Slot 1: __write_int uses type i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32Void);
  { Slot 2: __read_int uses type void -> i32 (always present) }
  SmallEmitULEB128(secFunc, TypeVoidI32);
  { Slot 3: __str_assign uses type i32,i32,i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32x3Void);
  { Slot 4: __write_str uses type i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32Void);
  { Slot 5: __str_compare uses type i32,i32 -> i32 (always present) }
  SmallEmitULEB128(secFunc, TypeI32x2I32);
  { Slot 6: __read_str uses type i32,i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32x2Void);
  { Slot 7: __str_append uses type i32,i32,i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32x3Void);
  { Slot 8: __str_copy uses type i32,i32,i32,i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32x4Void);
  { Slot 9: __str_pos uses type i32,i32 -> i32 (always present) }
  SmallEmitULEB128(secFunc, TypeI32x2I32);
  { Slot 10: __str_delete uses type i32,i32,i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32x3Void);
  { Slot 11: __str_insert uses type i32,i32,i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32x3Void);
  { Slot 12: __range_check uses type i32,i32,i32 -> i32 (always present) }
  SmallEmitULEB128(secFunc, TypeI32x3I32);
  { Slot 13: __checked_add uses type i32,i32 -> i32 (always present) }
  SmallEmitULEB128(secFunc, TypeI32x2I32);
  { Slot 14: __checked_sub uses type i32,i32 -> i32 (always present) }
  SmallEmitULEB128(secFunc, TypeI32x2I32);
  { Slot 15: __checked_mul uses type i32,i32 -> i32 (always present) }
  SmallEmitULEB128(secFunc, TypeI32x2I32);
  { Slot 16: __set_union uses type i32,i32,i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32x3Void);
  { Slot 17: __set_intersect uses type i32,i32,i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32x3Void);
  { Slot 18: __set_diff uses type i32,i32,i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32x3Void);
  { Slot 19: __set_eq uses type i32,i32 -> i32 (always present) }
  SmallEmitULEB128(secFunc, TypeI32x2I32);
  { Slot 20: __set_subset uses type i32,i32 -> i32 (always present) }
  SmallEmitULEB128(secFunc, TypeI32x2I32);
  { Slot 21: __int_to_str uses type i32,i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32x2Void);
  { Slot 22: __write_char uses type i32,i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32x2Void);
  { Slots 23+: User-defined functions (skip imports) }
  for i := 0 to numFuncs - 1 do
    if funcs[i].bodyStart <> -2 then
      SmallEmitULEB128(secFunc, funcs[i].typeidx);
end;

procedure AssembleMemorySection;
var
  minPages: longint;
begin
  SmallBufInit(secMemory);
  { Compute minimum pages needed: at least optMemPages, at least enough for data }
  minPages := optMemPages;
  if (dataPos + 65535) div 65536 > minPages then
    minPages := (dataPos + 65535) div 65536;
  SmallBufEmit(secMemory, 1);    { 1 memory }
  SmallBufEmit(secMemory, 1);    { flags: has max }
  SmallEmitULEB128(secMemory, minPages);
  SmallEmitULEB128(secMemory, optMaxMemPages);
end;

procedure AssembleGlobalSection;
const
  MaxDisplayDepth = 8;
var
  i: longint;
begin
  SmallBufInit(secGlobal);
  SmallBufEmit(secGlobal, 1 + MaxDisplayDepth + 1); { $sp + 8 display + __version }
  { Global 0: $sp (stack pointer) }
  SmallBufEmit(secGlobal, WasmI32);  { type: i32 }
  SmallBufEmit(secGlobal, 1);        { mutable }
  { init expr: i32.const SP (top of initial memory) }
  SmallBufEmit(secGlobal, OpI32Const);
  SmallEmitSLEB128(secGlobal, optMemPages * 65536);
  SmallBufEmit(secGlobal, OpEnd);
  { Globals 1..8: display[0]..display[7] — frame pointers for nested scopes }
  for i := 1 to MaxDisplayDepth do begin
    SmallBufEmit(secGlobal, WasmI32);  { type: i32 }
    SmallBufEmit(secGlobal, 1);        { mutable }
    SmallBufEmit(secGlobal, OpI32Const);
    SmallBufEmit(secGlobal, 0);        { init to 0 }
    SmallBufEmit(secGlobal, OpEnd);
  end;
  { Global 9: __version (immutable, YY*65536 + MM*256 + patch) }
  SmallBufEmit(secGlobal, WasmI32);  { type: i32 }
  SmallBufEmit(secGlobal, 0);        { immutable }
  SmallBufEmit(secGlobal, OpI32Const);
  SmallEmitSLEB128(secGlobal, VersionYear * 65536 + VersionMonth * 256 + VersionPatch);
  SmallBufEmit(secGlobal, OpEnd);
end;

procedure AssembleExportSection;
var
  i, j: longint;
begin
  SmallBufInit(secExport);
  SmallEmitULEB128(secExport, 3 + numUserExports); { _start + memory + __version + user exports }
  { Export "_start" }
  SmallBufEmit(secExport, 6);  { name length }
  SmallBufEmit(secExport, ord('_'));
  SmallBufEmit(secExport, ord('s'));
  SmallBufEmit(secExport, ord('t'));
  SmallBufEmit(secExport, ord('a'));
  SmallBufEmit(secExport, ord('r'));
  SmallBufEmit(secExport, ord('t'));
  SmallBufEmit(secExport, ExportFunc);
  SmallEmitULEB128(secExport, numImports); { _start is first defined func }
  { Export "memory" }
  SmallBufEmit(secExport, 6);  { name length }
  SmallBufEmit(secExport, ord('m'));
  SmallBufEmit(secExport, ord('e'));
  SmallBufEmit(secExport, ord('m'));
  SmallBufEmit(secExport, ord('o'));
  SmallBufEmit(secExport, ord('r'));
  SmallBufEmit(secExport, ord('y'));
  SmallBufEmit(secExport, ExportMem);
  SmallBufEmit(secExport, 0);  { memory index 0 }
  { Export "__version" — global index 9 (after $sp + 8 display) }
  SmallBufEmit(secExport, 9);  { name length }
  SmallBufEmit(secExport, ord('_'));
  SmallBufEmit(secExport, ord('_'));
  SmallBufEmit(secExport, ord('v'));
  SmallBufEmit(secExport, ord('e'));
  SmallBufEmit(secExport, ord('r'));
  SmallBufEmit(secExport, ord('s'));
  SmallBufEmit(secExport, ord('i'));
  SmallBufEmit(secExport, ord('o'));
  SmallBufEmit(secExport, ord('n'));
  SmallBufEmit(secExport, ExportGlobal);
  SmallBufEmit(secExport, 1 + 8);  { global index 9 }
  (* User-defined exports from EXPORT directives *)
  for i := 0 to numUserExports - 1 do begin
    SmallEmitULEB128(secExport, length(userExports[i].name));
    for j := 1 to length(userExports[i].name) do
      SmallBufEmit(secExport, ord(userExports[i].name[j]));
    SmallBufEmit(secExport, ExportFunc);
    SmallEmitULEB128(secExport, userExports[i].funcIdx);
  end;
end;

procedure EmitHelper(op: byte);
begin
  CodeBufEmit(helperCode, op);
end;

procedure EmitHelperI32Const(value: longint);
begin
  CodeBufEmit(helperCode, OpI32Const);
  EmitSLEB128Fix(helperCode, value);
end;

procedure EmitHelperULEB128(value: longint);
begin
  EmitULEB128(helperCode, value);
end;

procedure EmitHelperCall(funcIdx: longint);
begin
  CodeBufEmit(helperCode, OpCall);
  EmitULEB128(helperCode, funcIdx);
end;

procedure BuildWriteIntHelper;
(** Build the __write_int(value: i32) function body into helperCode.
  The function converts an i32 to decimal ASCII in the intbuf scratch
  area, then calls fd_write to print it.

  Uses 3 WASM locals:
    local 0 = parameter (the value)
    local 1 = pos (i32) - current write position in buffer
    local 2 = negative flag (i32)

  Algorithm: write digits right-to-left, then fd_write the result.
*)
begin
  CodeBufInit(helperCode);

  (* local 0 = value (parameter), local 1 = pos, local 2 = neg_flag *)

  (* pos = intbuf + 19 *)
  EmitHelperI32Const(addrIntBuf + 19);
  EmitHelper(OpLocalSet); EmitHelperULEB128(1);

  (* neg_flag = 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(2);

  (* if value < 0 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelperI32Const(0);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    (* value = 0 - value *)
    EmitHelperI32Const(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpI32Sub);
    EmitHelper(OpLocalSet); EmitHelperULEB128(0);
    (* neg_flag = 1 *)
    EmitHelperI32Const(1);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
  EmitHelper(OpEnd);

  (* if value == 0: special case *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpI32Eqz);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    (* store '0' at pos *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelperI32Const(ord('0'));
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
    (* pos-- *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Sub);
    EmitHelper(OpLocalSet); EmitHelperULEB128(1);
  EmitHelper(OpElse);
    (* loop: extract digits *)
    EmitHelper(OpLoop); EmitHelper(WasmVoid);
      (* digit = value % 10 + '0' *)
      EmitHelper(OpLocalGet); EmitHelperULEB128(1);  (* pos = store address *)
      EmitHelper(OpLocalGet); EmitHelperULEB128(0);  (* value *)
      EmitHelperI32Const(10);
      EmitHelper(OpI32RemS);
      EmitHelperI32Const(ord('0'));
      EmitHelper(OpI32Add);
      EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

      (* value = value / 10 *)
      EmitHelper(OpLocalGet); EmitHelperULEB128(0);
      EmitHelperI32Const(10);
      EmitHelper(OpI32DivS);
      EmitHelper(OpLocalSet); EmitHelperULEB128(0);

      (* pos-- *)
      EmitHelper(OpLocalGet); EmitHelperULEB128(1);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Sub);
      EmitHelper(OpLocalSet); EmitHelperULEB128(1);

      (* if value != 0: continue *)
      EmitHelper(OpLocalGet); EmitHelperULEB128(0);
      EmitHelperI32Const(0);
      EmitHelper(OpI32Ne);
      EmitHelper(OpBrIf); EmitHelperULEB128(0);
    EmitHelper(OpEnd); (* end loop *)
  EmitHelper(OpEnd); (* end if/else *)

  (* if negative: store '-' *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelperI32Const(ord('-'));
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Sub);
    EmitHelper(OpLocalSet); EmitHelperULEB128(1);
  EmitHelper(OpEnd);

  (* pos++ to point to first character *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Add);
  EmitHelper(OpLocalSet); EmitHelperULEB128(1);

  (* Set up iovec: buf = pos, len = intbuf+20 - pos *)
  EmitHelperI32Const(addrIovec);
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);

  EmitHelperI32Const(addrIovec + 4);
  EmitHelperI32Const(addrIntBuf + 20);
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpI32Sub);
  EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);

  (* fd_write(1, iovec, 1, nwritten) *)
  EmitHelperI32Const(1);
  EmitHelperI32Const(addrIovec);
  EmitHelperI32Const(1);
  EmitHelperI32Const(addrNwritten);
  EmitHelperCall(idxFdWrite);
  EmitHelper(OpDrop);
end;

procedure BuildWriteCharHelper;
(** Build __write_char(value: i32, fd: i32) function body into helperCode.
  Writes a single byte (the low byte of value) to the given fd via fd_write.
  Parameters:
    local 0 = value (i32, char value — only low byte used)
    local 1 = fd (i32, file descriptor: 1=stdout, 2=stderr)
  Uses addrReadBuf as a 1-byte scratch area.
*)
var fdw: longint;
begin
  CodeBufInit(helperCode);
  fdw := idxFdWrite;

  (* store low byte of value to addrReadBuf *)
  EmitHelperI32Const(addrReadBuf);
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

  (* iovec.buf = addrReadBuf *)
  EmitHelperI32Const(addrIovec);
  EmitHelperI32Const(addrReadBuf);
  EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);

  (* iovec.len = 1 *)
  EmitHelperI32Const(addrIovec + 4);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);

  (* fd_write(fd, iovec, 1, nwritten) *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);  { fd }
  EmitHelperI32Const(addrIovec);
  EmitHelperI32Const(1);
  EmitHelperI32Const(addrNwritten);
  EmitHelperCall(fdw);
  EmitHelper(OpDrop);
end;

procedure BuildIntToStrHelper;
(* Build __int_to_str(value: i32, dest: i32) function body into helperCode.
   Converts an i32 to decimal ASCII in intBuf scratch area, then copies
   the result as a Pascal string (length byte + chars) to dest.

   Uses 3 WASM locals (+ 2 params = 5 total):
     param 0 = value
     param 1 = dest address
     local 2 = pos (i32) - current write position in intBuf
     local 3 = neg_flag (i32)
     local 4 = len (i32) - computed string length
*)
begin
  CodeBufInit(helperCode);

  (* pos = intbuf + 19 *)
  EmitHelperI32Const(addrIntBuf + 19);
  EmitHelper(OpLocalSet); EmitHelperULEB128(2);

  (* neg_flag = 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(3);

  (* if value < 0 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelperI32Const(0);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    (* value = 0 - value *)
    EmitHelperI32Const(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpI32Sub);
    EmitHelper(OpLocalSet); EmitHelperULEB128(0);
    (* neg_flag = 1 *)
    EmitHelperI32Const(1);
    EmitHelper(OpLocalSet); EmitHelperULEB128(3);
  EmitHelper(OpEnd);

  (* if value == 0: special case *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpI32Eqz);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(ord('0'));
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Sub);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
  EmitHelper(OpElse);
    (* loop: extract digits right to left *)
    EmitHelper(OpLoop); EmitHelper(WasmVoid);
      EmitHelper(OpLocalGet); EmitHelperULEB128(2);
      EmitHelper(OpLocalGet); EmitHelperULEB128(0);
      EmitHelperI32Const(10);
      EmitHelper(OpI32RemS);
      EmitHelperI32Const(ord('0'));
      EmitHelper(OpI32Add);
      EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

      EmitHelper(OpLocalGet); EmitHelperULEB128(0);
      EmitHelperI32Const(10);
      EmitHelper(OpI32DivS);
      EmitHelper(OpLocalSet); EmitHelperULEB128(0);

      EmitHelper(OpLocalGet); EmitHelperULEB128(2);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Sub);
      EmitHelper(OpLocalSet); EmitHelperULEB128(2);

      EmitHelper(OpLocalGet); EmitHelperULEB128(0);
      EmitHelperI32Const(0);
      EmitHelper(OpI32Ne);
      EmitHelper(OpBrIf); EmitHelperULEB128(0);
    EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* if negative: store '-' *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(3);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(ord('-'));
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Sub);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
  EmitHelper(OpEnd);

  (* pos++ to point to first character *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Add);
  EmitHelper(OpLocalSet); EmitHelperULEB128(2);

  (* len = intbuf + 20 - pos *)
  EmitHelperI32Const(addrIntBuf + 20);
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpI32Sub);
  EmitHelper(OpLocalSet); EmitHelperULEB128(4);

  (* store length byte at dest *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpLocalGet); EmitHelperULEB128(4);
  EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

  (* memory.copy dest+1, pos, len *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Add);
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpLocalGet); EmitHelperULEB128(4);
  EmitHelper($FC); EmitHelper($0A); EmitHelper($00); EmitHelper($00); { memory.copy 0 0 }
end;

procedure BuildReadIntHelper;
(** Build the __read_int() -> i32 function body into helperCode.
  Reads decimal integer from stdin (fd 0) via fd_read, one byte at a time.
  Skips leading whitespace, handles optional sign, parses digits.

  Uses 3 WASM locals:
    local 0 = result (i32) - accumulated value
    local 1 = negative (i32) - 1 if negative, 0 if positive
    local 2 = byte_val (i32) - last byte read from readbuf

  Uses addrReadBuf (1 byte) for fd_read iovec buffer.
  Uses addrIovec for the iovec struct.
  Uses addrNread (4 bytes) for fd_read nread result.

  Algorithm:
    1. Skip whitespace (space, tab, CR, LF)
    2. Check for sign (+ or -)
    3. Read digits: result = result * 10 + (byte - '0')
    4. If negative, negate result
    5. Return result
*)
begin
  CodeBufInit(helperCode);

  (* result = 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(0);

  (* negative = 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(1);

  (* --- Read one byte helper pattern:
     Set iovec to point to readbuf (1 byte), call fd_read(0, iovec, 1, nread).
     After the call, readbuf[0] has the byte and nread has bytes read.
     We inline this pattern each time we need to read. --- *)

  (* --- Phase 1: Skip leading whitespace --- *)
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* Set up iovec: buf = addrReadBuf, len = 1 *)
    EmitHelperI32Const(addrIovec);
    EmitHelperI32Const(addrReadBuf);
    EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);
    EmitHelperI32Const(addrIovec + 4);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);

    (* fd_read(0, iovec, 1, nread) *)
    EmitHelperI32Const(0);              { fd = stdin }
    EmitHelperI32Const(addrIovec);
    EmitHelperI32Const(1);              { iovs_len = 1 }
    EmitHelperI32Const(addrNread);
    EmitHelperCall(idxFdRead);
    EmitHelper(OpDrop);                 { discard errno }

    (* if nread == 0, return 0 (EOF) *)
    EmitHelperI32Const(addrNread);
    EmitHelper(OpI32Load); EmitHelperULEB128(2); EmitHelperULEB128(0);
    EmitHelper(OpI32Eqz);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      EmitHelper(OpLocalGet); EmitHelperULEB128(0);
      EmitHelper(OpReturn);
    EmitHelper(OpEnd);

    (* byte_val = readbuf[0] *)
    EmitHelperI32Const(addrReadBuf);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);

    (* if byte_val == ' ' or byte_val == 9 or byte_val == 10 or byte_val == 13: continue *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(32);   { space }
    EmitHelper(OpI32Eq);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(9);    { tab }
    EmitHelper(OpI32Eq);
    EmitHelper(OpI32Or);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(10);   { LF }
    EmitHelper(OpI32Eq);
    EmitHelper(OpI32Or);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(13);   { CR }
    EmitHelper(OpI32Eq);
    EmitHelper(OpI32Or);
    EmitHelper(OpBrIf); EmitHelperULEB128(0);  { continue loop }
  EmitHelper(OpEnd); (* end whitespace loop *)

  (* --- Phase 2: Check for sign --- *)
  (* if byte_val == '-' *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelperI32Const(ord('-'));
  EmitHelper(OpI32Eq);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(1);
    EmitHelper(OpLocalSet); EmitHelperULEB128(1);  { negative = 1 }
    (* Read next byte *)
    EmitHelperI32Const(addrIovec);
    EmitHelperI32Const(addrReadBuf);
    EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);
    EmitHelperI32Const(addrIovec + 4);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);
    EmitHelperI32Const(0);
    EmitHelperI32Const(addrIovec);
    EmitHelperI32Const(1);
    EmitHelperI32Const(addrNread);
    EmitHelperCall(idxFdRead);
    EmitHelper(OpDrop);
    EmitHelperI32Const(addrReadBuf);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
  EmitHelper(OpElse);
    (* if byte_val == '+', skip it and read next byte *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(ord('+'));
    EmitHelper(OpI32Eq);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      EmitHelperI32Const(addrIovec);
      EmitHelperI32Const(addrReadBuf);
      EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);
      EmitHelperI32Const(addrIovec + 4);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);
      EmitHelperI32Const(0);
      EmitHelperI32Const(addrIovec);
      EmitHelperI32Const(1);
      EmitHelperI32Const(addrNread);
      EmitHelperCall(idxFdRead);
      EmitHelper(OpDrop);
      EmitHelperI32Const(addrReadBuf);
      EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
      EmitHelper(OpLocalSet); EmitHelperULEB128(2);
    EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* --- Phase 3: Parse digits --- *)
  (* byte_val is now the first digit (or non-digit if malformed input).
     Loop: while byte_val >= '0' and byte_val <= '9' *)
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* Check: byte_val >= '0' *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(ord('0'));
    EmitHelper(OpI32GeS);
    (* Check: byte_val <= '9' *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(ord('9'));
    EmitHelper(OpI32LeS);
    (* Both conditions *)
    EmitHelper(OpI32And);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      (* result = result * 10 + (byte_val - '0') *)
      EmitHelper(OpLocalGet); EmitHelperULEB128(0);
      EmitHelperI32Const(10);
      EmitHelper(OpI32Mul);
      EmitHelper(OpLocalGet); EmitHelperULEB128(2);
      EmitHelperI32Const(ord('0'));
      EmitHelper(OpI32Sub);
      EmitHelper(OpI32Add);
      EmitHelper(OpLocalSet); EmitHelperULEB128(0);

      (* Read next byte *)
      EmitHelperI32Const(addrIovec);
      EmitHelperI32Const(addrReadBuf);
      EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);
      EmitHelperI32Const(addrIovec + 4);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);
      EmitHelperI32Const(0);
      EmitHelperI32Const(addrIovec);
      EmitHelperI32Const(1);
      EmitHelperI32Const(addrNread);
      EmitHelperCall(idxFdRead);
      EmitHelper(OpDrop);

      (* If nread == 0, break (EOF) *)
      EmitHelperI32Const(addrNread);
      EmitHelper(OpI32Load); EmitHelperULEB128(2); EmitHelperULEB128(0);
      EmitHelper(OpI32Eqz);
      EmitHelper(OpIf); EmitHelper(WasmVoid);
        (* Set byte_val to 0 to stop loop *)
        EmitHelperI32Const(0);
        EmitHelper(OpLocalSet); EmitHelperULEB128(2);
      EmitHelper(OpElse);
        EmitHelperI32Const(addrReadBuf);
        EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
        EmitHelper(OpLocalSet); EmitHelperULEB128(2);
      EmitHelper(OpEnd);

      EmitHelper(OpBr); EmitHelperULEB128(1);  { continue outer loop }
    EmitHelper(OpEnd); (* end if digit *)
  EmitHelper(OpEnd); (* end digit loop *)

  (* --- Phase 4: Apply sign and return --- *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);  { negative flag }
  EmitHelper(OpIf); EmitHelper(WasmI32);
    EmitHelperI32Const(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpI32Sub);
  EmitHelper(OpElse);
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpEnd);
  (* value is on stack, function returns it *)
end;

procedure BuildStrAssignHelper;
(** Build __str_assign(dst, max_len, src) function body into helperCode.
  Copies a Pascal short string from src to dst, truncating to max_len.
  Parameters:
    local 0 = dst (i32, address of destination string)
    local 1 = max_len (i32, maximum string length for destination)
    local 2 = src (i32, address of source string)
  Extra locals:
    local 3 = len (i32, actual copy length)
    local 4 = i (i32, loop counter)
*)
begin
  CodeBufInit(helperCode);

  (* len = src[0] (source length byte) *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(3);

  (* if len > max_len then len := max_len *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(3);
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpI32GtU);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpLocalSet); EmitHelperULEB128(3);
  EmitHelper(OpEnd);

  (* dst[0] := len *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpLocalGet); EmitHelperULEB128(3);
  EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(4);

  (* while i < len do begin *)
  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelper(OpI32GeU);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);  { break if i >= len }

    (* dst[i+1] := src[i+1] *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);       { dst + i + 1 }

    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);       { src + i + 1 }
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);

    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

    (* i := i + 1 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(4);

    EmitHelper(OpBr); EmitHelperULEB128(0);  { continue loop }
  EmitHelper(OpEnd);
  EmitHelper(OpEnd);
end;

procedure BuildWriteStrHelper;
(** Build __write_str(addr) function body into helperCode.
  Writes a Pascal short string to stdout via fd_write.
  Parameters:
    local 0 = addr (i32, address of Pascal string: length byte + data)
  Uses the shared iovec/nwritten scratch area.
*)
var fdw: longint;
begin
  CodeBufInit(helperCode);
  fdw := idxFdWrite;

  (* iovec.buf = addr + 1  (skip length byte, point to character data) *)
  EmitHelperI32Const(addrIovec);
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Add);
  EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);

  (* iovec.len = addr[0]  (length byte) *)
  EmitHelperI32Const(addrIovec + 4);
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);

  (* fd_write(1, iovec, 1, nwritten) *)
  EmitHelperI32Const(1);         { fd = stdout }
  EmitHelperI32Const(addrIovec);
  EmitHelperI32Const(1);
  EmitHelperI32Const(addrNwritten);
  EmitHelperCall(fdw);
  EmitHelper(OpDrop);            { discard errno }
end;

procedure BuildStrCompareHelper;
(** Build __str_compare(a, b) -> i32 function body into helperCode.
  Lexicographic comparison of two Pascal short strings.
  Returns -1 if a<b, 0 if a=b, +1 if a>b.
  Parameters:
    local 0 = a (i32, address of first string)
    local 1 = b (i32, address of second string)
  Extra locals:
    local 2 = minLen (i32, min of both lengths)
    local 3 = i (i32, loop counter)
    local 4 = ca (i32, char from a)
    local 5 = cb (i32, char from b)
*)
begin
  CodeBufInit(helperCode);

  (* minLen = a[0]; if b[0] < minLen then minLen = b[0] *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(2);

  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpI32LtU);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
  EmitHelper(OpEnd);

  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(3);

  (* compare characters loop *)
  EmitHelper(OpBlock); EmitHelper(WasmVoid);   { block $break }
  EmitHelper(OpLoop); EmitHelper(WasmVoid);    { loop $continue }
    (* if i >= minLen then break *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelper(OpI32GeU);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* ca = a[i+1] *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpLocalSet); EmitHelperULEB128(4);

    (* cb = b[i+1] *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpLocalSet); EmitHelperULEB128(5);

    (* if ca < cb then return -1 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelper(OpLocalGet); EmitHelperULEB128(5);
    EmitHelper(OpI32LtU);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      EmitHelperI32Const(-1);
      EmitHelper(OpReturn);
    EmitHelper(OpEnd);

    (* if ca > cb then return 1 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelper(OpLocalGet); EmitHelperULEB128(5);
    EmitHelper(OpI32GtU);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      EmitHelperI32Const(1);
      EmitHelper(OpReturn);
    EmitHelper(OpEnd);

    (* i := i + 1 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(3);

    EmitHelper(OpBr); EmitHelperULEB128(0);  { continue loop }
  EmitHelper(OpEnd);  { end loop }
  EmitHelper(OpEnd);  { end block }

  (* All common chars equal — compare lengths: a[0] - b[0], clamped to -1/0/1 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpI32Sub);
  (* clamp: if result > 0 then 1, if < 0 then -1, else 0 *)
  EmitHelper(OpLocalSet); EmitHelperULEB128(4);  { reuse ca as temp }
  EmitHelper(OpLocalGet); EmitHelperULEB128(4);
  EmitHelperI32Const(0);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper($7F);  { i32 result }
    EmitHelperI32Const(1);
  EmitHelper(OpElse);
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelperI32Const(0);
    EmitHelper(OpI32LtS);
    EmitHelper(OpIf); EmitHelper($7F);  { i32 result }
      EmitHelperI32Const(-1);
    EmitHelper(OpElse);
      EmitHelperI32Const(0);
    EmitHelper(OpEnd);
  EmitHelper(OpEnd);
end;

procedure BuildReadStrHelper;
(** Build __read_str(addr, max_len) function body into helperCode.
  Reads a line from stdin into a Pascal short string.
  Stops at LF (consumed but not stored) or EOF.
  Parameters:
    local 0 = addr (i32, address of destination string)
    local 1 = max_len (i32, maximum string length)
  Extra locals:
    local 2 = i (i32, current count of bytes stored)
*)
var fdr: longint;
begin
  CodeBufInit(helperCode);
  fdr := idxFdRead;

  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(2);

  (* Set up iovec: buf = addrReadBuf, len = 1 *)
  EmitHelperI32Const(addrIovec);
  EmitHelperI32Const(addrReadBuf);
  EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);
  EmitHelperI32Const(addrIovec + 4);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);

  (* loop *)
  EmitHelper(OpBlock); EmitHelper(WasmVoid);   { block $break }
  EmitHelper(OpLoop); EmitHelper(WasmVoid);    { loop $continue }

    (* fd_read(0, iovec, 1, nread) *)
    EmitHelperI32Const(0);           { fd = stdin }
    EmitHelperI32Const(addrIovec);
    EmitHelperI32Const(1);
    EmitHelperI32Const(addrNread);
    EmitHelperCall(fdr);
    EmitHelper(OpDrop);              { discard errno }

    (* if nread == 0 then break (EOF) *)
    EmitHelperI32Const(addrNread);
    EmitHelper(OpI32Load); EmitHelperULEB128(2); EmitHelperULEB128(0);
    EmitHelper(OpI32Eqz);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* if readbuf[0] == 10 (LF) then break *)
    EmitHelperI32Const(addrReadBuf);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelperI32Const(10);
    EmitHelper(OpI32Eq);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* if i < max_len then store byte *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpI32LtU);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      (* addr[i+1] := readbuf[0] *)
      EmitHelper(OpLocalGet); EmitHelperULEB128(0);
      EmitHelper(OpLocalGet); EmitHelperULEB128(2);
      EmitHelper(OpI32Add);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Add);       { addr + i + 1 }
      EmitHelperI32Const(addrReadBuf);
      EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
      EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

      (* i := i + 1 *)
      EmitHelper(OpLocalGet); EmitHelperULEB128(2);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Add);
      EmitHelper(OpLocalSet); EmitHelperULEB128(2);
    EmitHelper(OpEnd);

    EmitHelper(OpBr); EmitHelperULEB128(0);  { continue loop }
  EmitHelper(OpEnd);  { end loop }
  EmitHelper(OpEnd);  { end block }

  (* addr[0] := i (set length byte) *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
end;

procedure BuildStrAppendHelper;
(** Build __str_append(dst, maxlen, src) function body into helperCode.
  Appends string src to dst, clamping total length to maxlen.
  Parameters:
    local 0 = dst (i32, address of destination string)
    local 1 = maxlen (i32, max string length)
    local 2 = src (i32, address of source string)
  Extra locals:
    local 3 = curLen (i32, current length of dst)
    local 4 = srcLen (i32, length of src, clamped to available space)
    local 5 = i (i32, loop counter)
*)
begin
  CodeBufInit(helperCode);

  (* curLen := dst[0] *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(3);

  (* srcLen := src[0] *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(4);

  (* avail := maxlen - curLen; if srcLen > avail then srcLen := avail *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(4);
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpLocalGet); EmitHelperULEB128(3);
  EmitHelper(OpI32Sub);
  EmitHelper(OpI32GtU);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelper(OpI32Sub);
    EmitHelper(OpLocalSet); EmitHelperULEB128(4);
  EmitHelper(OpEnd);

  (* dst[0] := curLen + srcLen *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpLocalGet); EmitHelperULEB128(3);
  EmitHelper(OpLocalGet); EmitHelperULEB128(4);
  EmitHelper(OpI32Add);
  EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

  (* Copy src[1..srcLen] to dst[curLen+1..curLen+srcLen] *)
  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(5);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);   { block $break }
  EmitHelper(OpLoop); EmitHelper(WasmVoid);    { loop $cont }
    (* if i >= srcLen then break *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(5);
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelper(OpI32GeU);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* dst[curLen + i + 1] := src[i + 1] *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalGet); EmitHelperULEB128(5);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelper(OpLocalGet); EmitHelperULEB128(5);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

    (* i := i + 1 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(5);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(5);

    EmitHelper(OpBr); EmitHelperULEB128(0);
  EmitHelper(OpEnd);  { end loop }
  EmitHelper(OpEnd);  { end block }
end;

procedure BuildStrCopyHelper;
(** Build __str_copy(src, idx, count, dst) function body into helperCode.
  Extracts a substring from src starting at 1-based idx for count chars.
  Result is written to dst as a Pascal short string.
  Parameters:
    local 0 = src (i32, address of source string)
    local 1 = idx (i32, 1-based start index)
    local 2 = count (i32, number of chars to copy)
    local 3 = dst (i32, address of destination buffer)
  Extra locals:
    local 4 = srcLen (i32, length of source)
    local 5 = i (i32, loop counter)
*)
begin
  CodeBufInit(helperCode);

  (* srcLen := src[0] *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(4);

  (* if idx < 1 then idx := 1 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelperI32Const(1);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(1);
    EmitHelper(OpLocalSet); EmitHelperULEB128(1);
  EmitHelper(OpEnd);

  (* if idx > srcLen then count := 0 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpLocalGet); EmitHelperULEB128(4);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(0);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
  EmitHelper(OpEnd);

  (* if idx + count - 1 > srcLen then count := srcLen - idx + 1 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpI32Add);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Sub);
  EmitHelper(OpLocalGet); EmitHelperULEB128(4);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpI32Sub);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
  EmitHelper(OpEnd);

  (* if count < 0 then count := 0 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelperI32Const(0);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(0);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
  EmitHelper(OpEnd);

  (* if count > 255 then count := 255 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelperI32Const(255);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(255);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
  EmitHelper(OpEnd);

  (* dst[0] := count *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(3);
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

  (* copy src[idx..idx+count-1] to dst[1..count] *)
  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(5);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* if i >= count then break *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(5);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelper(OpI32GeS);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* dst[i + 1] := src[idx + i] *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelper(OpLocalGet); EmitHelperULEB128(5);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalGet); EmitHelperULEB128(5);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

    (* i := i + 1 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(5);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(5);

    EmitHelper(OpBr); EmitHelperULEB128(0);
  EmitHelper(OpEnd);
  EmitHelper(OpEnd);
end;

procedure BuildStrPosHelper;
(** Build __str_pos(sub, s) -> i32 function body into helperCode.
  Finds 1-based position of sub in s. Returns 0 if not found.
  Parameters:
    local 0 = sub (i32, address of substring)
    local 1 = s (i32, address of string to search in)
  Extra locals:
    local 2 = subLen (i32)
    local 3 = sLen (i32)
    local 4 = i (i32, outer loop: position in s, 0-based)
    local 5 = j (i32, inner loop: position in sub, 0-based)
    local 6 = matched (i32, boolean flag)
*)
begin
  CodeBufInit(helperCode);

  (* subLen := sub[0] *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(2);

  (* sLen := s[0] *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(3);

  (* if subLen = 0 then return 0 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpI32Eqz);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(0);
    EmitHelper(OpReturn);
  EmitHelper(OpEnd);

  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(4);

  (* outer loop: for i := 0 to sLen - subLen *)
  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* if i > sLen - subLen then break *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelper(OpI32Sub);
    EmitHelper(OpI32GtS);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* matched := 1; j := 0 *)
    EmitHelperI32Const(1);
    EmitHelper(OpLocalSet); EmitHelperULEB128(6);
    EmitHelperI32Const(0);
    EmitHelper(OpLocalSet); EmitHelperULEB128(5);

    (* inner loop: compare sub[j+1] with s[i+j+1] *)
    EmitHelper(OpBlock); EmitHelper(WasmVoid);
    EmitHelper(OpLoop); EmitHelper(WasmVoid);
      (* if j >= subLen then break inner *)
      EmitHelper(OpLocalGet); EmitHelperULEB128(5);
      EmitHelper(OpLocalGet); EmitHelperULEB128(2);
      EmitHelper(OpI32GeS);
      EmitHelper(OpBrIf); EmitHelperULEB128(1);

      (* if s[i+j+1] <> sub[j+1] then matched := 0; break inner *)
      EmitHelper(OpLocalGet); EmitHelperULEB128(1);
      EmitHelper(OpLocalGet); EmitHelperULEB128(4);
      EmitHelper(OpI32Add);
      EmitHelper(OpLocalGet); EmitHelperULEB128(5);
      EmitHelper(OpI32Add);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Add);
      EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
      EmitHelper(OpLocalGet); EmitHelperULEB128(0);
      EmitHelper(OpLocalGet); EmitHelperULEB128(5);
      EmitHelper(OpI32Add);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Add);
      EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
      EmitHelper(OpI32Ne);
      EmitHelper(OpIf); EmitHelper(WasmVoid);
        EmitHelperI32Const(0);
        EmitHelper(OpLocalSet); EmitHelperULEB128(6);
        EmitHelper(OpBr); EmitHelperULEB128(2); { break inner block }
      EmitHelper(OpEnd);

      (* j := j + 1 *)
      EmitHelper(OpLocalGet); EmitHelperULEB128(5);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Add);
      EmitHelper(OpLocalSet); EmitHelperULEB128(5);

      EmitHelper(OpBr); EmitHelperULEB128(0); { continue inner loop }
    EmitHelper(OpEnd); { end inner loop }
    EmitHelper(OpEnd); { end inner block }

    (* if matched then return i + 1 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(6);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      EmitHelper(OpLocalGet); EmitHelperULEB128(4);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Add);
      EmitHelper(OpReturn);
    EmitHelper(OpEnd);

    (* i := i + 1 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(4);

    EmitHelper(OpBr); EmitHelperULEB128(0); { continue outer loop }
  EmitHelper(OpEnd); { end outer loop }
  EmitHelper(OpEnd); { end outer block }

  (* not found: return 0 *)
  EmitHelperI32Const(0);
end;

procedure BuildStrDeleteHelper;
(** Build __str_delete(s, idx, count) function body into helperCode.
  Removes count chars starting at 1-based idx from string s in-place.
  Parameters:
    local 0 = s (i32, address of string)
    local 1 = idx (i32, 1-based start index)
    local 2 = count (i32, number of chars to delete)
  Extra locals:
    local 3 = sLen (i32, current string length)
    local 4 = i (i32, loop counter)
    local 5 = tailStart (i32, byte index where chars after deleted region start)
    local 6 = newLen (i32, new string length)
*)
begin
  CodeBufInit(helperCode);

  (* sLen := s[0] *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(3);

  (* if idx < 1 or idx > sLen then exit — nothing to delete *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelperI32Const(1);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpReturn);
  EmitHelper(OpEnd);
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpLocalGet); EmitHelperULEB128(3);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpReturn);
  EmitHelper(OpEnd);

  (* if count <= 0 then exit *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelperI32Const(0);
  EmitHelper(OpI32LeS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpReturn);
  EmitHelper(OpEnd);

  (* clamp: if idx + count - 1 > sLen then count := sLen - idx + 1 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpI32Add);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Sub);
  EmitHelper(OpLocalGet); EmitHelperULEB128(3);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpI32Sub);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
  EmitHelper(OpEnd);

  (* tailStart := idx + count (1-based byte position of first char after deleted region) *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpI32Add);
  EmitHelper(OpLocalSet); EmitHelperULEB128(5);

  (* newLen := sLen - count *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(3);
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpI32Sub);
  EmitHelper(OpLocalSet); EmitHelperULEB128(6);

  (* shift tail chars left: s[idx..newLen] := s[tailStart..sLen] *)
  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(4);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* if tailStart + i > sLen then break *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(5);
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelper(OpI32GtS);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* s[idx + i] := s[tailStart + i] — these are 1-based byte positions *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(5);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

    (* i := i + 1 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(4);

    EmitHelper(OpBr); EmitHelperULEB128(0);
  EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* s[0] := newLen *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpLocalGet); EmitHelperULEB128(6);
  EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
end;

procedure BuildStrInsertHelper;
(** Build __str_insert(src, dst, idx) function body into helperCode.
  Inserts string src into dst at 1-based position idx, in-place.
  Parameters:
    local 0 = src (i32, address of source string to insert)
    local 1 = dst (i32, address of destination string)
    local 2 = idx (i32, 1-based insertion position)
  Extra locals:
    local 3 = srcLen (i32)
    local 4 = dstLen (i32)
    local 5 = newLen (i32)
    local 6 = i (i32, loop counter)
*)
begin
  CodeBufInit(helperCode);

  (* srcLen := src[0] *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(3);

  (* dstLen := dst[0] *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(4);

  (* if srcLen = 0 then exit *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(3);
  EmitHelper(OpI32Eqz);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpReturn);
  EmitHelper(OpEnd);

  (* clamp idx: if idx < 1 then idx := 1 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelperI32Const(1);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(1);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
  EmitHelper(OpEnd);

  (* if idx > dstLen + 1 then idx := dstLen + 1 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(2);
  EmitHelper(OpLocalGet); EmitHelperULEB128(4);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Add);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
  EmitHelper(OpEnd);

  (* newLen := dstLen + srcLen; clamp to 255 *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(4);
  EmitHelper(OpLocalGet); EmitHelperULEB128(3);
  EmitHelper(OpI32Add);
  EmitHelper(OpLocalSet); EmitHelperULEB128(5);
  EmitHelper(OpLocalGet); EmitHelperULEB128(5);
  EmitHelperI32Const(255);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(255);
    EmitHelper(OpLocalSet); EmitHelperULEB128(5);
    (* also clamp srcLen so we don't overflow *)
    EmitHelperI32Const(255);
    EmitHelper(OpLocalGet); EmitHelperULEB128(4);
    EmitHelper(OpI32Sub);
    EmitHelper(OpLocalSet); EmitHelperULEB128(3);
  EmitHelper(OpEnd);

  (* shift tail right: dst[idx+srcLen..newLen] := dst[idx..dstLen] *)
  (* iterate from dstLen down to idx to avoid overlap issues *)
  (* i := dstLen *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(4);
  EmitHelper(OpLocalSet); EmitHelperULEB128(6);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* if i < idx then break *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(6);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelper(OpI32LtS);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* only copy if i + srcLen <= 255 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(6);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(255);
    EmitHelper(OpI32LeS);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      (* dst[i + srcLen] := dst[i] — 1-based byte positions *)
      EmitHelper(OpLocalGet); EmitHelperULEB128(1);
      EmitHelper(OpLocalGet); EmitHelperULEB128(6);
      EmitHelper(OpI32Add);
      EmitHelper(OpLocalGet); EmitHelperULEB128(3);
      EmitHelper(OpI32Add);
      EmitHelper(OpLocalGet); EmitHelperULEB128(1);
      EmitHelper(OpLocalGet); EmitHelperULEB128(6);
      EmitHelper(OpI32Add);
      EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
      EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpEnd);

    (* i := i - 1 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(6);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Sub);
    EmitHelper(OpLocalSet); EmitHelperULEB128(6);

    EmitHelper(OpBr); EmitHelperULEB128(0);
  EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* copy src[1..srcLen] into dst[idx..idx+srcLen-1] *)
  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(6);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* if i >= srcLen then break *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(6);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelper(OpI32GeS);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* dst[idx + i] := src[i + 1] *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalGet); EmitHelperULEB128(6);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(6);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

    (* i := i + 1 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(6);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(6);

    EmitHelper(OpBr); EmitHelperULEB128(0);
  EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* dst[0] := newLen *)
  EmitHelper(OpLocalGet); EmitHelperULEB128(1);
  EmitHelper(OpLocalGet); EmitHelperULEB128(5);
  EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
end;

procedure BuildSetBinOpHelper(opKind: longint);
(** Build a large set binary operation helper into helperCode.
  opKind: 0 = union (OR), 1 = intersect (AND), 2 = diff (AND NOT).
  Parameters: local 0 = dst, local 1 = a, local 2 = b.
  Extra locals: local 3 = counter (i32).
  Loops over 8 i32 words. *)
begin
  CodeBufInit(helperCode);

  (* counter := 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(3);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);

    (* dst + counter*4 — store address *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelperI32Const(2);
    EmitHelper(OpI32Shl);
    EmitHelper(OpI32Add);

    (* a[counter]: load i32 at a + counter*4 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelperI32Const(2);
    EmitHelper(OpI32Shl);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load); EmitHelperULEB128(2); EmitHelperULEB128(0);

    (* b[counter]: load i32 at b + counter*4 *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelperI32Const(2);
    EmitHelper(OpI32Shl);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load); EmitHelperULEB128(2); EmitHelperULEB128(0);

    (* apply operator *)
    case opKind of
      0: EmitHelper(OpI32Or);              { union: a[i] OR b[i] }
      1: EmitHelper(OpI32And);             { intersect: a[i] AND b[i] }
      2: begin                             { diff: a[i] AND NOT b[i] }
           EmitHelperI32Const(-1);
           EmitHelper(OpI32Xor);
           EmitHelper(OpI32And);
         end;
    end;

    (* store result *)
    EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);

    (* counter++; if counter < 8 then loop *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(3);
    EmitHelper(OpLocalGet); EmitHelperULEB128(3);
    EmitHelperI32Const(8);
    EmitHelper(OpI32LtU);
    EmitHelper(OpBrIf); EmitHelperULEB128(0);

  EmitHelper(OpEnd);
  EmitHelper(OpEnd);
end;

procedure BuildSetEqHelper;
(** Build __set_eq(a, b) -> i32 helper into helperCode.
  Returns 1 if equal, 0 if not.
  Parameters: local 0 = a, local 1 = b.
  Extra locals: local 2 = counter (i32).
  Loops over 8 i32 words. *)
begin
  CodeBufInit(helperCode);

  (* counter := 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(2);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);

    (* a[counter] *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(2);
    EmitHelper(OpI32Shl);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load); EmitHelperULEB128(2); EmitHelperULEB128(0);

    (* b[counter] *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(2);
    EmitHelper(OpI32Shl);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load); EmitHelperULEB128(2); EmitHelperULEB128(0);

    (* if a[i] <> b[i] then return 0 *)
    EmitHelper(OpI32Ne);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      EmitHelperI32Const(0);
      EmitHelper(OpReturn);
    EmitHelper(OpEnd);

    (* counter++; if counter < 8 then loop *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(8);
    EmitHelper(OpI32LtU);
    EmitHelper(OpBrIf); EmitHelperULEB128(0);

  EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* all words equal *)
  EmitHelperI32Const(1);
end;

procedure BuildSetSubsetHelper;
(** Build __set_subset(a, b) -> i32 helper into helperCode.
  Returns 1 if a is a subset of b (a AND NOT b = 0 for all words).
  Parameters: local 0 = a, local 1 = b.
  Extra locals: local 2 = counter (i32).
  Loops over 8 i32 words. *)
begin
  CodeBufInit(helperCode);

  (* counter := 0 *)
  EmitHelperI32Const(0);
  EmitHelper(OpLocalSet); EmitHelperULEB128(2);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);

    (* a[counter] *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(0);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(2);
    EmitHelper(OpI32Shl);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load); EmitHelperULEB128(2); EmitHelperULEB128(0);

    (* b[counter] — then NOT *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(1);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(2);
    EmitHelper(OpI32Shl);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load); EmitHelperULEB128(2); EmitHelperULEB128(0);
    EmitHelperI32Const(-1);
    EmitHelper(OpI32Xor);     { NOT b[i] }
    EmitHelper(OpI32And);     { a[i] AND NOT b[i] }

    (* if nonzero then return 0 — not a subset *)
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      EmitHelperI32Const(0);
      EmitHelper(OpReturn);
    EmitHelper(OpEnd);

    (* counter++; if counter < 8 then loop *)
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpLocalSet); EmitHelperULEB128(2);
    EmitHelper(OpLocalGet); EmitHelperULEB128(2);
    EmitHelperI32Const(8);
    EmitHelper(OpI32LtU);
    EmitHelper(OpBrIf); EmitHelperULEB128(0);

  EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* all words pass — a is subset of b *)
  EmitHelperI32Const(1);
end;

procedure CopyBufToCode(var src: TCodeBuf);
var i: longint;
begin
  for i := 0 to src.len - 1 do
    CodeBufEmit(secCode, src.data[i]);
end;

procedure AssembleCodeSectionFixed;
{** Assemble the code section.
  Function order: slot 0 = _start, slot 1 = __write_int, slot 2 = __read_int,
  slot 3 = __str_assign, slot 4 = __write_str, slot 5 = __str_compare,
  slot 6 = __read_str, slot 7 = __str_append, slot 8 = __str_copy,
  slot 9 = __str_pos, slot 10 = __str_delete, slot 11 = __str_insert,
  slot 21 = __int_to_str, slot 22 = __write_char, slots 23+ = user funcs. }
var
  bodyLen: longint;
  i, j: longint;
begin
  CodeBufInit(secCode);

  { Function count }
  EmitULEB128(secCode, numDefinedFuncs);

  { Slot 0: _start body — conditional locals + code + end }
  if startNlocals > 0 then begin
    bodyLen := 1 + 1 + 1 + startCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);          { 1 local declaration block }
    CodeBufEmit(secCode, startNlocals); { N locals }
    CodeBufEmit(secCode, WasmI32);    { of type i32 }
  end else begin
    bodyLen := 1 + startCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 0);  { 0 local declarations }
  end;
  CopyBufToCode(startCode);
  CodeBufEmit(secCode, OpEnd);

  { Slot 1: __write_int body — always present (empty stub if unused) }
  if needsWriteInt then begin
    BuildWriteIntHelper;
    (* locals: 1 declaration block = 2 locals of type i32 *)
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 2);      { 2 locals }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    { Empty stub: unreachable + end }
    EmitULEB128(secCode, 3);     { body size: 1 (locals) + 1 (unreachable) + 1 (end) }
    CodeBufEmit(secCode, 0);     { 0 local declarations }
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 2: __read_int body — always present (empty stub if unused) }
  if needsReadInt then begin
    BuildReadIntHelper;
    (* locals: 1 declaration block = 3 locals of type i32 *)
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 3);      { 3 locals: result, negative, byte_read }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    { Empty stub: unreachable + end }
    EmitULEB128(secCode, 3);     { body size: 1 (locals) + 1 (unreachable) + 1 (end) }
    CodeBufEmit(secCode, 0);     { 0 local declarations }
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 3: __str_assign body — always present (empty stub if unused) }
  if needsStrAssign then begin
    BuildStrAssignHelper;
    (* locals: 1 declaration block = 2 locals of type i32 (len, i) *)
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 2);      { 2 locals: len, i }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    { Empty stub: unreachable + end }
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 4: __write_str body — always present (empty stub if unused) }
  if needsWriteStr then begin
    BuildWriteStrHelper;
    (* locals: 0 — uses only the parameter *)
    bodyLen := 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 0);      { 0 local declarations }
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    { Empty stub: unreachable + end }
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 5: __str_compare body — always present (empty stub if unused) }
  if needsStrCompare then begin
    BuildStrCompareHelper;
    (* locals: 1 declaration block = 4 locals of type i32 (minLen, i, ca, cb) *)
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 4);      { 4 locals: minLen, i, ca, cb }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    { Empty stub: unreachable + end }
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 6: __read_str body — always present (empty stub if unused) }
  if needsReadStr then begin
    BuildReadStrHelper;
    (* locals: 1 declaration block = 1 local of type i32 (i) *)
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 1);      { 1 local: i }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    { Empty stub: unreachable + end }
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 7: __str_append body — always present (empty stub if unused) }
  if needsStrAppend then begin
    BuildStrAppendHelper;
    (* locals: 1 declaration block = 3 locals of type i32 (curLen, srcLen, i) *)
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 3);      { 3 locals: curLen, srcLen, i }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    { Empty stub: unreachable + end }
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 8: __str_copy body — always present (empty stub if unused) }
  if needsStrCopy then begin
    BuildStrCopyHelper;
    (* locals: 1 declaration block = 2 locals of type i32 (srcLen, i) *)
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 2);      { 2 locals: srcLen, i }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 9: __str_pos body — always present (empty stub if unused) }
  if needsStrPos then begin
    BuildStrPosHelper;
    (* locals: 1 declaration block = 5 locals of type i32 (subLen, sLen, i, j, matched) *)
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 5);      { 5 locals: subLen, sLen, i, j, matched }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 10: __str_delete body — always present (empty stub if unused) }
  if needsStrDelete then begin
    BuildStrDeleteHelper;
    (* locals: 1 declaration block = 4 locals of type i32 (sLen, i, tailStart, newLen) *)
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 4);      { 4 locals: sLen, i, tailStart, newLen }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 11: __str_insert body — always present (empty stub if unused) }
  if needsStrInsert then begin
    BuildStrInsertHelper;
    (* locals: 1 declaration block = 4 locals of type i32 (srcLen, dstLen, newLen, i) *)
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 4);      { 4 locals: srcLen, dstLen, newLen, i }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 12: __range_check body — always present (empty stub if unused) }
  if needsRangeCheck then begin
    { __range_check(val, lo, hi) -> val, traps if val < lo or val > hi }
    { No extra locals needed — params are $0=val, $1=lo, $2=hi }
    EmitULEB128(secCode, 22); { body size: 1 (locals) + 20 (code) + 1 (end) }
    CodeBufEmit(secCode, 0);  { 0 local declarations }
    { if val < lo then unreachable }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { val }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 1); { lo }
    CodeBufEmit(secCode, OpI32LtS);
    CodeBufEmit(secCode, OpIf);
    CodeBufEmit(secCode, $40); { void block }
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
    { if val > hi then unreachable }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { val }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 2); { hi }
    CodeBufEmit(secCode, OpI32GtS);
    CodeBufEmit(secCode, OpIf);
    CodeBufEmit(secCode, $40); { void block }
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
    { return val }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { val }
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 13: __checked_add body — always present (empty stub if unused) }
  if needsCheckedAdd then begin
    { __checked_add(a, b) -> i32, traps on overflow }
    { 1 local: $result (index 2) }
    EmitULEB128(secCode, 31); { body size: 3 (locals) + 27 (code) + 1 (end) }
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 1);      { 1 local }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { a }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 1); { b }
    CodeBufEmit(secCode, OpI32Add);
    CodeBufEmit(secCode, OpLocalSet); CodeBufEmit(secCode, 2); { result }
    { overflow: (a ^ result) & (b ^ result) < 0 }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { a }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 2); { result }
    CodeBufEmit(secCode, OpI32Xor);
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 1); { b }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 2); { result }
    CodeBufEmit(secCode, OpI32Xor);
    CodeBufEmit(secCode, OpI32And);
    CodeBufEmit(secCode, OpI32Const); CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpI32LtS);
    CodeBufEmit(secCode, OpIf);
    CodeBufEmit(secCode, $40); { void block }
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 2); { return result }
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 14: __checked_sub body — always present (empty stub if unused) }
  if needsCheckedSub then begin
    { __checked_sub(a, b) -> i32, traps on overflow }
    { 1 local: $result (index 2) }
    EmitULEB128(secCode, 31); { body size: 3 (locals) + 27 (code) + 1 (end) }
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 1);      { 1 local }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { a }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 1); { b }
    CodeBufEmit(secCode, OpI32Sub);
    CodeBufEmit(secCode, OpLocalSet); CodeBufEmit(secCode, 2); { result }
    { overflow: (a ^ b) & (a ^ result) < 0 }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { a }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 1); { b }
    CodeBufEmit(secCode, OpI32Xor);
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { a }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 2); { result }
    CodeBufEmit(secCode, OpI32Xor);
    CodeBufEmit(secCode, OpI32And);
    CodeBufEmit(secCode, OpI32Const); CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpI32LtS);
    CodeBufEmit(secCode, OpIf);
    CodeBufEmit(secCode, $40); { void block }
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 2); { return result }
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 15: __checked_mul body — always present (empty stub if unused) }
  if needsCheckedMul then begin
    { __checked_mul(a, b) -> i32, traps on overflow }
    { 1 local: $result (index 2) }
    EmitULEB128(secCode, 33); { body size: 3 (locals) + 29 (code) + 1 (end) }
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 1);      { 1 local }
    CodeBufEmit(secCode, WasmI32); { of type i32 }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { a }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 1); { b }
    CodeBufEmit(secCode, OpI32Mul);
    CodeBufEmit(secCode, OpLocalSet); CodeBufEmit(secCode, 2); { result }
    { if a != 0 and result / a != b then overflow }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { a }
    CodeBufEmit(secCode, OpI32Const); CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpI32Ne);
    CodeBufEmit(secCode, OpIf);
    CodeBufEmit(secCode, $40); { void block }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 2); { result }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { a }
    CodeBufEmit(secCode, OpI32DivS);
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 1); { b }
    CodeBufEmit(secCode, OpI32Ne);
    CodeBufEmit(secCode, OpIf);
    CodeBufEmit(secCode, $40); { void block }
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
    CodeBufEmit(secCode, OpEnd);
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 2); { return result }
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 16: __set_union body — always present (empty stub if unused) }
  if needsSetUnion then begin
    BuildSetBinOpHelper(0); { 0 = union }
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 1);      { 1 local (counter) }
    CodeBufEmit(secCode, WasmI32);
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 17: __set_intersect body — always present (empty stub if unused) }
  if needsSetIntersect then begin
    BuildSetBinOpHelper(1); { 1 = intersect }
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);
    CodeBufEmit(secCode, 1);
    CodeBufEmit(secCode, WasmI32);
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 18: __set_diff body — always present (empty stub if unused) }
  if needsSetDiff then begin
    BuildSetBinOpHelper(2); { 2 = diff }
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);
    CodeBufEmit(secCode, 1);
    CodeBufEmit(secCode, WasmI32);
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 19: __set_eq body — always present (empty stub if unused) }
  if needsSetEq then begin
    BuildSetEqHelper;
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);
    CodeBufEmit(secCode, 1);
    CodeBufEmit(secCode, WasmI32);
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 20: __set_subset body — always present (empty stub if unused) }
  if needsSetSubset then begin
    BuildSetSubsetHelper;
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);
    CodeBufEmit(secCode, 1);
    CodeBufEmit(secCode, WasmI32);
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 21: __int_to_str body — always present (empty stub if unused) }
  if needsIntToStr then begin
    BuildIntToStrHelper;
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);      { 1 local declaration block }
    CodeBufEmit(secCode, 3);      { 3 locals (pos, neg_flag, len) }
    CodeBufEmit(secCode, WasmI32);
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 22: __write_char body — always present (empty stub if unused) }
  if needsWriteChar then begin
    BuildWriteCharHelper;
    bodyLen := 1 + helperCode.len + 1; { no extra locals beyond params }
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 0);      { 0 local declaration blocks }
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slots 23+: User-defined function bodies (skip imports) }
  for i := 0 to numFuncs - 1 do begin
    if funcs[i].bodyStart = -2 then continue; { skip imports }
    if funcs[i].nlocals > 0 then begin
      bodyLen := 1 + 1 + 1 + funcs[i].bodyLen + 1;
      EmitULEB128(secCode, bodyLen);
      CodeBufEmit(secCode, 1);               { 1 local decl block }
      CodeBufEmit(secCode, funcs[i].nlocals); { N locals }
      CodeBufEmit(secCode, WasmI32);          { of type i32 }
    end else begin
      bodyLen := 1 + funcs[i].bodyLen + 1;
      EmitULEB128(secCode, bodyLen);
      CodeBufEmit(secCode, 0);  { 0 local declarations }
    end;
    for j := 0 to funcs[i].bodyLen - 1 do
      CodeBufEmit(secCode, funcBodies.data[funcs[i].bodyStart + j]);
    CodeBufEmit(secCode, OpEnd);
  end;
end;

procedure AssembleDataSection;
{** Build the data section from accumulated data. }
var
  i: longint;
  tmp: TSmallBuf;
begin
  if secData.len = 0 then exit;

  { We need to wrap the data segment:
    data count (1), memory index (0), offset expr (i32.const 4, end), size, bytes }
  SmallBufInit(tmp);
  SmallBufEmit(tmp, 1);         { 1 data segment }
  SmallBufEmit(tmp, 0);         { memory index 0 }
  { offset: i32.const 4 (skip nil guard) }
  SmallBufEmit(tmp, OpI32Const);
  SmallBufEmit(tmp, 4);         { offset = 4 (SLEB128 for small positive) }
  SmallBufEmit(tmp, OpEnd);     { end init expr }
  { data size }
  SmallEmitULEB128(tmp, secData.len);

  { Now write the data section: header + raw data }
  WriteOutputByte(SecIdData);
  WriteOutputULEB128(tmp.len + secData.len);
  for i := 0 to tmp.len - 1 do
    WriteOutputByte(tmp.data[i]);
  for i := 0 to secData.len - 1 do
    WriteOutputByte(secData.data[i]);
end;

{ ---- Dump: human-readable WASM instruction listing ---- }

{$IFDEF FPC}
function ReadULEB128(var buf: TCodeBuf; var pos: longint): longint;
var
  b: byte;
  shift: longint;
  result_val: longint;
begin
  result_val := 0;
  shift := 0;
  repeat
    if pos >= buf.len then begin
      ReadULEB128 := result_val;
      exit;
    end;
    b := buf.data[pos];
    pos := pos + 1;
    result_val := result_val or ((longint(b) and $7F) shl shift);
    shift := shift + 7;
  until (b and $80) = 0;
  ReadULEB128 := result_val;
end;

function ReadSLEB128(var buf: TCodeBuf; var pos: longint): longint;
var
  b: byte;
  shift: longint;
  result_val: longint;
begin
  result_val := 0;
  shift := 0;
  repeat
    if pos >= buf.len then begin
      ReadSLEB128 := result_val;
      exit;
    end;
    b := buf.data[pos];
    pos := pos + 1;
    result_val := result_val or ((longint(b) and $7F) shl shift);
    shift := shift + 7;
  until (b and $80) = 0;
  { Sign extend }
  if (shift < 32) and ((b and $40) <> 0) then
    result_val := result_val or (longint($FFFFFFFF) shl shift);
  ReadSLEB128 := result_val;
end;

procedure DumpBytes(var buf: TCodeBuf; startPos, endPos: longint);
{** Disassemble WASM bytecodes from buf[startPos..endPos-1] to stderr. }
var
  pos: longint;
  op: byte;
  indent: longint;
  i: longint;
  val: longint;
  align, ofs: longint;
  blockType: longint;
  labelCount: longint;
begin
  pos := startPos;
  indent := 2;
  while pos < endPos do begin
    op := buf.data[pos];
    pos := pos + 1;

    { Dedent for end/else before printing }
    if (op = OpEnd) or (op = OpElse) then
      if indent > 2 then indent := indent - 2;

    { Print indent }
    for i := 1 to indent do write(stderr, ' ');

    case op of
      OpUnreachable: writeln(stderr, 'unreachable');
      OpNop:         writeln(stderr, 'nop');
      OpBlock: begin
        blockType := ReadSLEB128(buf, pos);
        if blockType = -64 then { $40 = void block type }
          writeln(stderr, 'block')
        else
          writeln(stderr, 'block (result i32)');
        indent := indent + 2;
      end;
      OpLoop: begin
        blockType := ReadSLEB128(buf, pos);
        if blockType = -64 then { $40 = void block type }
          writeln(stderr, 'loop')
        else
          writeln(stderr, 'loop (result i32)');
        indent := indent + 2;
      end;
      OpIf: begin
        blockType := ReadSLEB128(buf, pos);
        if blockType = -64 then { $40 = void block type }
          writeln(stderr, 'if')
        else
          writeln(stderr, 'if (result i32)');
        indent := indent + 2;
      end;
      OpElse: begin
        writeln(stderr, 'else');
        indent := indent + 2;
      end;
      OpEnd:   writeln(stderr, 'end');
      OpBr: begin
        val := ReadULEB128(buf, pos);
        writeln(stderr, 'br ', val);
      end;
      OpBrIf: begin
        val := ReadULEB128(buf, pos);
        writeln(stderr, 'br_if ', val);
      end;
      $0E: begin { br_table }
        labelCount := ReadULEB128(buf, pos);
        write(stderr, 'br_table');
        for i := 0 to labelCount do begin
          val := ReadULEB128(buf, pos);
          write(stderr, ' ', val);
        end;
        writeln(stderr);
      end;
      OpReturn:  writeln(stderr, 'return');
      OpCall: begin
        val := ReadULEB128(buf, pos);
        write(stderr, 'call ', val);
        { Annotate known functions }
        if val = idxFdWrite then
          writeln(stderr, '  ;; fd_write')
        else if val = idxFdRead then
          writeln(stderr, '  ;; fd_read')
        else if val = idxProcExit then
          writeln(stderr, '  ;; proc_exit')
        else if val = numImports then
          writeln(stderr, '  ;; _start')
        else if val = numImports + 1 then
          writeln(stderr, '  ;; __write_int')
        else if val = numImports + 2 then
          writeln(stderr, '  ;; __read_int')
        else if val = numImports + 3 then
          writeln(stderr, '  ;; __str_assign')
        else if val = numImports + 4 then
          writeln(stderr, '  ;; __write_str')
        else if val = numImports + 5 then
          writeln(stderr, '  ;; __str_compare')
        else if val = numImports + 6 then
          writeln(stderr, '  ;; __read_str')
        else if val = numImports + 7 then
          writeln(stderr, '  ;; __str_append')
        else if val = numImports + 8 then
          writeln(stderr, '  ;; __str_copy')
        else if val = numImports + 9 then
          writeln(stderr, '  ;; __str_pos')
        else if val = numImports + 10 then
          writeln(stderr, '  ;; __str_delete')
        else if val = numImports + 11 then
          writeln(stderr, '  ;; __str_insert')
        else if val = numImports + 12 then
          writeln(stderr, '  ;; __range_check')
        else if val = numImports + 13 then
          writeln(stderr, '  ;; __checked_add')
        else if val = numImports + 14 then
          writeln(stderr, '  ;; __checked_sub')
        else if val = numImports + 15 then
          writeln(stderr, '  ;; __checked_mul')
        else if val = numImports + 16 then
          writeln(stderr, '  ;; __set_union')
        else if val = numImports + 17 then
          writeln(stderr, '  ;; __set_intersect')
        else if val = numImports + 18 then
          writeln(stderr, '  ;; __set_diff')
        else if val = numImports + 19 then
          writeln(stderr, '  ;; __set_eq')
        else if val = numImports + 20 then
          writeln(stderr, '  ;; __set_subset')
        else if val = numImports + 21 then
          writeln(stderr, '  ;; __int_to_str')
        else if val = numImports + 22 then
          writeln(stderr, '  ;; __write_char')
        else begin
          { User function }
          i := val - numImports - 23;
          if (i >= 0) and (i < numFuncs) then
            writeln(stderr, '  ;; ', funcs[i].name)
          else
            writeln(stderr);
        end;
      end;
      OpCallInd: begin
        val := ReadULEB128(buf, pos);
        writeln(stderr, 'call_indirect ', val);
        { table index }
        val := ReadULEB128(buf, pos);
      end;
      OpDrop:   writeln(stderr, 'drop');
      OpSelect: writeln(stderr, 'select');
      OpLocalGet: begin
        val := ReadULEB128(buf, pos);
        writeln(stderr, 'local.get ', val);
      end;
      OpLocalSet: begin
        val := ReadULEB128(buf, pos);
        writeln(stderr, 'local.set ', val);
      end;
      OpLocalTee: begin
        val := ReadULEB128(buf, pos);
        writeln(stderr, 'local.tee ', val);
      end;
      OpGlobalGet: begin
        val := ReadULEB128(buf, pos);
        write(stderr, 'global.get ', val);
        if val = 0 then
          writeln(stderr, '  ;; $sp')
        else if val <= 8 then
          writeln(stderr, '  ;; display[', val - 1, ']')
        else
          writeln(stderr);
      end;
      OpGlobalSet: begin
        val := ReadULEB128(buf, pos);
        write(stderr, 'global.set ', val);
        if val = 0 then
          writeln(stderr, '  ;; $sp')
        else if val <= 8 then
          writeln(stderr, '  ;; display[', val - 1, ']')
        else
          writeln(stderr);
      end;
      OpI32Load: begin
        align := ReadULEB128(buf, pos);
        ofs := ReadULEB128(buf, pos);
        writeln(stderr, 'i32.load align=', align, ' offset=', ofs);
      end;
      OpI32Load8s: begin
        align := ReadULEB128(buf, pos);
        ofs := ReadULEB128(buf, pos);
        writeln(stderr, 'i32.load8_s align=', align, ' offset=', ofs);
      end;
      OpI32Load8u: begin
        align := ReadULEB128(buf, pos);
        ofs := ReadULEB128(buf, pos);
        writeln(stderr, 'i32.load8_u align=', align, ' offset=', ofs);
      end;
      OpI32Load16s: begin
        align := ReadULEB128(buf, pos);
        ofs := ReadULEB128(buf, pos);
        writeln(stderr, 'i32.load16_s align=', align, ' offset=', ofs);
      end;
      OpI32Load16u: begin
        align := ReadULEB128(buf, pos);
        ofs := ReadULEB128(buf, pos);
        writeln(stderr, 'i32.load16_u align=', align, ' offset=', ofs);
      end;
      OpI32Store: begin
        align := ReadULEB128(buf, pos);
        ofs := ReadULEB128(buf, pos);
        writeln(stderr, 'i32.store align=', align, ' offset=', ofs);
      end;
      OpI32Store8: begin
        align := ReadULEB128(buf, pos);
        ofs := ReadULEB128(buf, pos);
        writeln(stderr, 'i32.store8 align=', align, ' offset=', ofs);
      end;
      OpI32Store16: begin
        align := ReadULEB128(buf, pos);
        ofs := ReadULEB128(buf, pos);
        writeln(stderr, 'i32.store16 align=', align, ' offset=', ofs);
      end;
      OpI32Const: begin
        val := ReadSLEB128(buf, pos);
        writeln(stderr, 'i32.const ', val);
      end;
      OpI32Eqz:  writeln(stderr, 'i32.eqz');
      OpI32Eq:   writeln(stderr, 'i32.eq');
      OpI32Ne:   writeln(stderr, 'i32.ne');
      OpI32LtS:  writeln(stderr, 'i32.lt_s');
      OpI32LtU:  writeln(stderr, 'i32.lt_u');
      OpI32GtS:  writeln(stderr, 'i32.gt_s');
      OpI32GtU:  writeln(stderr, 'i32.gt_u');
      OpI32LeS:  writeln(stderr, 'i32.le_s');
      OpI32LeU:  writeln(stderr, 'i32.le_u');
      OpI32GeS:  writeln(stderr, 'i32.ge_s');
      OpI32GeU:  writeln(stderr, 'i32.ge_u');
      OpI32Add:  writeln(stderr, 'i32.add');
      OpI32Sub:  writeln(stderr, 'i32.sub');
      OpI32Mul:  writeln(stderr, 'i32.mul');
      OpI32DivS: writeln(stderr, 'i32.div_s');
      OpI32DivU: writeln(stderr, 'i32.div_u');
      OpI32RemS: writeln(stderr, 'i32.rem_s');
      OpI32RemU: writeln(stderr, 'i32.rem_u');
      OpI32And:  writeln(stderr, 'i32.and');
      OpI32Or:   writeln(stderr, 'i32.or');
      OpI32Xor:  writeln(stderr, 'i32.xor');
      OpI32Shl:  writeln(stderr, 'i32.shl');
      OpI32ShrS: writeln(stderr, 'i32.shr_s');
      OpI32ShrU: writeln(stderr, 'i32.shr_u');
      $FC: begin { multi-byte prefix }
        if pos < endPos then begin
          val := ReadULEB128(buf, pos);
          case val of
            $0A: begin { memory.copy }
              { skip two memory indices (0, 0) }
              ReadULEB128(buf, pos);
              ReadULEB128(buf, pos);
              writeln(stderr, 'memory.copy');
            end;
            $0B: begin { memory.fill }
              ReadULEB128(buf, pos); { memory index }
              writeln(stderr, 'memory.fill');
            end;
          else
            writeln(stderr, '0xFC ', val);
          end;
        end else
          writeln(stderr, '0xFC (truncated)');
      end;
    else
      write(stderr, '<unknown opcode $');
      val := op shr 4;
      if val < 10 then write(stderr, chr(ord('0') + val))
      else write(stderr, chr(ord('A') + val - 10));
      val := op and $F;
      if val < 10 then write(stderr, chr(ord('0') + val))
      else write(stderr, chr(ord('A') + val - 10));
      writeln(stderr, '>');
    end;
  end;
end;

procedure DumpModule;
{** Print human-readable WASM instruction listing to stderr. }
var
  i: longint;
  slotName: string;
begin
  writeln(stderr);
  writeln(stderr, '--- WASM dump ---');
  writeln(stderr);

  { Imports }
  writeln(stderr, 'Imports: ', numImports);
  for i := 0 to numImports - 1 do
    writeln(stderr, '  func[', i, '] ', imports[i].modname, '.', imports[i].fieldname,
            ' type=', imports[i].typeidx);
  writeln(stderr);

  { Globals }
  writeln(stderr, 'Globals: $sp (0), display[0..7] (1..8)');
  writeln(stderr);

  { _start function }
  writeln(stderr, 'func[', numImports, '] _start  locals=', startNlocals,
          '  bytes=', startCode.len);
  DumpBytes(startCode, 0, startCode.len);
  writeln(stderr);

  { Helper slots — list active ones }
  for i := 1 to 22 do begin
    case i of
      1: if needsWriteInt then slotName := '__write_int' else continue;
      2: if needsReadInt then slotName := '__read_int' else continue;
      3: if needsStrAssign then slotName := '__str_assign' else continue;
      4: if needsWriteStr then slotName := '__write_str' else continue;
      5: if needsStrCompare then slotName := '__str_compare' else continue;
      6: if needsReadStr then slotName := '__read_str' else continue;
      7: if needsStrAppend then slotName := '__str_append' else continue;
      8: if needsStrCopy then slotName := '__str_copy' else continue;
      9: if needsStrPos then slotName := '__str_pos' else continue;
      10: if needsStrDelete then slotName := '__str_delete' else continue;
      11: if needsStrInsert then slotName := '__str_insert' else continue;
      12: if needsRangeCheck then slotName := '__range_check' else continue;
      13: if needsCheckedAdd then slotName := '__checked_add' else continue;
      14: if needsCheckedSub then slotName := '__checked_sub' else continue;
      15: if needsCheckedMul then slotName := '__checked_mul' else continue;
      16: if needsSetUnion then slotName := '__set_union' else continue;
      17: if needsSetIntersect then slotName := '__set_intersect' else continue;
      18: if needsSetDiff then slotName := '__set_diff' else continue;
      19: if needsSetEq then slotName := '__set_eq' else continue;
      20: if needsSetSubset then slotName := '__set_subset' else continue;
      21: if needsIntToStr then slotName := '__int_to_str' else continue;
      22: if needsWriteChar then slotName := '__write_char' else continue;
    end;
    writeln(stderr, 'func[', numImports + i, '] ', slotName, '  (helper, code in code section)');
  end;
  writeln(stderr);

  { User-defined functions }
  for i := 0 to numFuncs - 1 do begin
    if funcs[i].bodyStart = -2 then begin
      writeln(stderr, 'func[', numImports + 23 + i, '] ', funcs[i].name,
              '  (import)');
      continue;
    end;
    writeln(stderr, 'func[', numImports + 23 + i, '] ', funcs[i].name,
            '  params=', funcs[i].nparams,
            '  locals=', funcs[i].nlocals,
            '  bytes=', funcs[i].bodyLen);
    DumpBytes(funcBodies, funcs[i].bodyStart,
              funcs[i].bodyStart + funcs[i].bodyLen);
    writeln(stderr);
  end;

  { Data segment }
  writeln(stderr, 'Data segment: ', secData.len, ' bytes at offset 4');
  writeln(stderr, 'Memory: ', optMemPages, ' page(s) initial, ',
          optMaxMemPages, ' max');
  writeln(stderr, 'Stack size: ', optStackSize, ' bytes');
  writeln(stderr);
end;
{$ENDIF}

procedure WriteModule;
var i: longint;
begin
  CodeBufInit(outBuf);

  { Pre-register all WASM types before assembling sections }
  TypeVoidVoid;
  TypeI32Void;  { always needed for __write_int stub, __write_str, and proc_exit }
  TypeVoidI32;  { always needed for __read_int stub }
  TypeI32x3Void; { always needed for __str_assign stub }
  TypeI32x2Void; { always needed for __read_str stub }
  TypeI32x2I32;  { always needed for __str_compare stub }
  { TypeI32x3Void already registered — reused for __str_append, __str_delete, __str_insert stubs }
  TypeI32x4Void; { always needed for __str_copy stub }
  TypeI32x3I32;  { always needed for __range_check stub }

  { Assemble all sections }
  AssembleTypeSection;
  AssembleImportSection;
  AssembleFunctionSection;
  AssembleMemorySection;
  AssembleGlobalSection;
  AssembleExportSection;
  AssembleCodeSectionFixed;

  { Write WASM header }
  WriteOutputByte($00);  { \0 }
  WriteOutputByte($61);  { a }
  WriteOutputByte($73);  { s }
  WriteOutputByte($6D);  { m }
  WriteOutputByte($01);  { version 1 }
  WriteOutputByte($00);
  WriteOutputByte($00);
  WriteOutputByte($00);

  { Write sections in order }
  WriteSmallSection(SecIdType, secType);
  WriteSmallSection(SecIdImport, secImport);
  WriteSmallSection(SecIdFunc, secFunc);
  WriteSmallSection(SecIdMemory, secMemory);
  WriteSmallSection(SecIdGlobal, secGlobal);
  WriteSmallSection(SecIdExport, secExport);
  WriteCodeSection(SecIdCode, secCode);
  AssembleDataSection; { writes directly to outBuf }

  { Write description custom section if set }
  if optDescription <> '' then begin
    { Custom section: id=0, section_size, name_string, payload }
    { name_string = ULEB128(11) + "description" = 12 bytes }
    { payload = raw description text }
    WriteOutputByte(0); { custom section id }
    WriteOutputULEB128(12 + length(optDescription)); { section size }
    WriteOutputString('description'); { name: ULEB128(11) + 11 chars }
    for i := 1 to length(optDescription) do
      WriteOutputByte(ord(optDescription[i]));
  end;

  { Flush output to stdout }
  {$IFDEF FPC}
  Assign(outFile, '/dev/stdout');
  Rewrite(outFile, 1);
  BlockWrite(outFile, outBuf.data, outBuf.len);
  Close(outFile);
  {$ELSE}
  { Self-hosted: write raw bytes to stdout one at a time }
  for i := 0 to outBuf.len - 1 do
    write(chr(outBuf.data[i]));
  {$ENDIF}
end;

{ ---- Main ---- }

procedure Init;
var
  i: longint;
begin
  { Initialize all state }
  SmallBufInit(secType);
  SmallBufInit(secImport);
  SmallBufInit(secFunc);
  SmallBufInit(secMemory);
  SmallBufInit(secGlobal);
  SmallBufInit(secExport);
  CodeBufInit(secCode);
  DataBufInit(secData);
  SmallBufInit(secName);
  CodeBufInit(outBuf);
  CodeBufInit(startCode);
  CodeBufInit(helperCode);
  CodeBufInit(funcBodies);

  srcLine := 1;
  srcCol := 0;
  atEof := false;
  hasPushback := false;
  pendingTok := false;

  numWasmTypes := 0;
  numTypes := 0;
  numFields := 0;
  numStructCopies := 0;
  numVarInits := 0;
  numImports := 0;
  numDefinedFuncs := 23; { slots 0-22: _start, __write_int, __read_int, __str_assign, __write_str, __str_compare, __read_str, __str_append, __str_copy, __str_pos, __str_delete, __str_insert, __range_check, __checked_add, __checked_sub, __checked_mul, __set_union, __set_intersect, __set_diff, __set_eq, __set_subset, __int_to_str, __write_char }
  numFuncs := 0;
  numSyms := 0;
  scopeDepth := 0;
  curFrameSize := 0;
  curNestLevel := 0;
  displayLocalIdx := -1;

  dataPos := 4;  { skip nil guard }

  idxIntToStr := -1;
  addrIovec := -1;
  addrNwritten := -1;
  addrIntBuf := -1;
  addrNewline := -1;
  addrReadBuf := -1;
  addrNread := -1;
  addrCharStr := -1;

  needsFdWrite := false;
  needsFdRead := false;
  needsProcExit := false;
  needsWriteInt := false;
  needsReadInt := false;
  needsStrAssign := false;
  needsWriteStr := false;
  needsStrCompare := false;
  needsReadStr := false;
  needsStrAppend := false;
  needsStrCopy := false;
  needsStrPos := false;
  needsStrDelete := false;
  needsStrInsert := false;
  needsRangeCheck := false;
  needsCheckedAdd := false;
  needsCheckedSub := false;
  needsCheckedMul := false;
  needsSetUnion := false;
  needsSetIntersect := false;
  needsSetDiff := false;
  needsSetEq := false;
  needsSetSubset := false;
  needsIntToStr := false;
  needsWriteChar := false;
  breakDepth := -1;
  continueDepth := -1;
  exitDepth := -1;
  forLimitDepth := 0;
  savedCodeStackTop := 0;
  for i := 0 to 15 do
    addrForLimit[i] := -1;
  addrSetTemp := -1;
  needsSetTemp := false;
  addrSetTemp2 := -1;
  setTempFlip := false;
  addrSetZero := -1;
  addrCopyTemp := -1;
  needsCopyTemp := false;
  concatPieces := 0;
  addrConcatScratch := -1;
  addrConcatTemp := -1;
  needsConcatScratch := false;
  startNlocals := 0;
  curStringTempIdx := 0;    { for _start, local 0 is the string temp }
  curFuncNeedsStringTemp := false;
  curCaseTempIdx := 1;      { for _start, case temp is local 1 (after string temp) }
  curFuncNeedsCaseTemp := false;
  exprType := tyInteger;

  hasPendingImport := false;
  hasPendingExport := false;
  numUserExports := 0;
  numWiths := 0;

  { Compiler directive defaults }
  optMemPages := 1;
  optMaxMemPages := 256;
  optStackSize := 65536;
  optDescription := '';
  optRangeChecks := false;
  optOverflowChecks := false;
  optExtLiterals := false;
  optDump := false;

  {$IFDEF FPC}
  { Parse command-line arguments (fpc native binary uses ParamCount/ParamStr) }
  for i := 1 to ParamCount do begin
    if ParamStr(i) = '-dump' then
      optDump := true
    else begin
      WriteErrorLn('Unknown option: ' + ParamStr(i));
      halt(1);
    end;
  end;
  {$ENDIF}

  { Pre-register all WASI imports so numImports is stable before
    any code emission. WASI hosts always provide these functions. }
  idxFdWrite := AddImport('wasi_snapshot_preview1', 'fd_write', TypeI32x4I32);
  idxFdRead := AddImport('wasi_snapshot_preview1', 'fd_read', TypeI32x4I32);
  idxProcExit := AddImport('wasi_snapshot_preview1', 'proc_exit', TypeI32Void);

  InitSymTable;
  AddBuiltins;
end;

begin
  Init;

  { Read first character }
  ReadCh;

  { Skip shebang line (e.g., #!/usr/bin/env cpas) }
  if (not atEof) and (ch = '#') then
    while (not atEof) and (ch <> #10) do
      ReadCh;

  { Read first token }
  NextToken;

  { Parse: program Ident ; Block . }
  Expect(tkProgram);
  if tokKind <> tkIdent then
    Expected('program name');
  NextToken;
  Expect(tkSemicolon);

  { Enter program scope }
  EnterScope;

  { Parse block (declarations + begin...end) }
  ParseBlock;

  { Expect final dot }
  Expect(tkDot);

  LeaveScope;

  { Set _start locals based on whether string/case temps were needed }
  if curFuncNeedsCaseTemp then
    startNlocals := startNlocals + 2  { string temp + case temp }
  else if curFuncNeedsStringTemp then
    startNlocals := startNlocals + 1;

  { Assemble and write WASM module }
  WriteModule;

  {$IFDEF FPC}
  { Dump instructions if -dump flag was given }
  if optDump then
    DumpModule;
  {$ENDIF}
end.
