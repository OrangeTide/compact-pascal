{$MODE TP}
{$IFNDEF FPC}
{$MEMORY 192}
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
  Version = '26.08.0';
  VersionYear = 26;
  VersionMonth = 08;
  VersionPatch = 0;

  { Section buffer sizes }
  SmallBufMax = 4095;    { 4 KB for small sections }
  CodeBufMax  = 196607;  { 192 KB for code section }
  DataBufMax  = 131071;  { 128 KB for data section }

  { Symbol table limits }
  MaxSyms    = 1024;
  MaxScopes  = 32;
  MaxFuncs   = 256;   { max user-defined functions }
  { WASM global indices: 0 = $sp, 1..8 = display[0..7], 9 = __version,
    10 = __heap_end. }
  GlobalHeapEnd = 10;

  MaxIfdefDepth = 8;  { max nested IFDEF levels }
  MaxDefines    = 32; (* max conditional symbols: predefined + DEFINE + -d *)

  { Stage count reported by -progress when the host gives no line count.
    Parsing start and end, one per assembled WASM section, then Done. }
  ProgressStages = 10;
  ProgressReports = 100; { max line-mode reports over the whole source }

  { Command-line args (WASI args_get) }
  MaxArgs     = 16;    { max command-line args (including argv[0]) }
  ArgSlotSize = 256;   { per-arg short-string slot: length byte + up to 255 chars }
  ArgBufCap   = 1024;  { raw C-string buffer size for all args }

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
  OpI64Const    = $42;
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
  tyPointer   = 9;

  { Type descriptor table limits }
  MaxTypes    = 256;
  MaxFields   = 512;
  MaxPendingPtr = 32;   { unresolved forward pointer references per type block }
  { 17 slots of 4 bytes per nesting level, four levels deep. }
  ConcatScratchBytes = 272;

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
    { Peephole window state. When PEEPHOLE is compiled in, these track the
      start positions of the two most recent complete instructions so the
      optimizer can pattern-match over them. -1 means "no instruction here".
      Fields exist unconditionally to keep the record layout stable. }
    lastOpStart: longint;
    prevOpStart: longint;
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
  TWasmParamArr = array[0..16] of byte;  { 16 visible params plus a hidden result pointer }
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
    variantOfs: longint; { byte offset where variant part begins, -1 if none }
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
    variantId: longint;  { 0 for fixed-part fields, 1..n for variant fields }
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
    paramTyp: array[0..15] of longint;    { param type tags, for forward-header checking }
    paramTypeIdx: array[0..15] of longint; { types[] index per param, -1 for simple }
    { A function returning a structured type takes a hidden trailing parameter
      holding the address of a buffer the caller allocated, and returns no
      WASM value. retSize is the buffer size in bytes; retTyp is tyNone for a
      procedure or a scalar-returning function. }
    retTyp: longint;
    retTypeIdx: longint;
    retSize: longint;
    retStrMax: longint;
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

  { Pointer types naming a type that is not declared yet. Pascal allows this
    one break from declare-before-use because a linked list cannot be written
    without it: PNode = ^TNode must precede the TNode that mentions PNode.
    The reference is resolved at the end of the type declaration block that
    opened it, and is an error if the name never appears. }
  pendingPtrType: array[0..MaxPendingPtr-1] of longint;  { types[] index }
  pendingPtrName: array[0..MaxPendingPtr-1] of string[63];
  pendingPtrLine: array[0..MaxPendingPtr-1] of longint;
  numPendingPtr: longint;

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
  idxArgsSizesGet: longint; { args_sizes_get import index }
  idxArgsGet: longint;     { args_get import index }
  idxPathOpen: longint;    { path_open import index, -1 until FILES is on }
  optFileIO: boolean;      { whether filesystem access was requested }
  emittedAnyCode: boolean; { true once any function body has been emitted }
  idxFdClose: longint;     { fd_close import index }
  idxIntToStr: longint;    { int-to-string helper, -1 if not emitted }

  { Data segment addresses for I/O scratch areas }
  addrIovec: longint;      { 8-byte iovec struct }
  addrNwritten: longint;   { 4-byte fd_write result }
  addrIntBuf: longint;     { 66-byte integer conversion buffer }
  addrNewline: longint;    { 1-byte newline character }
  addrReadBuf: longint;    { 1-byte fd_read buffer }
  addrNread: longint;      { 4-byte fd_read result }
  addrCharStr: longint;    { 2-byte scratch for char-to-string conversion }

  { Command-line args (WASI args_sizes_get / args_get) }
  addrArgc: longint;       { 4-byte argc (filled by args_sizes_get) }
  addrArgBufSize: longint; { 4-byte buffer size (filled by args_sizes_get) }
  addrArgv: longint;       { MaxArgs * 4 bytes: argv pointers }
  addrArgBuf: longint;     { ArgBufCap bytes: raw C-string buffer }
  addrArgSlots: longint;   { MaxArgs * ArgSlotSize bytes: short-string slots }
  needsArgs: boolean;      { whether ParamCount/ParamStr were used }
  argsInitCode: TCodeBuf;  { init code prepended to _start }

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
  needsNilCheck: boolean;        { __nil_check helper needed }
  needsHeap: boolean;            { __heap_alloc / __heap_free helpers needed }
  addrHeapFree: longint;         { data word holding the free list head }
  addrSetTemp: longint;          { 32-byte temp for large set arithmetic results }
  needsSetTemp: boolean;         { whether set temp was allocated }
  addrSetTemp2: longint;         { second 32-byte temp for compound set expressions }
  setTempFlip: boolean;          { toggle between addrSetTemp and addrSetTemp2 }
  addrSetZero: longint;          { static 32-byte zero block for [] with large sets }
  addrCopyTemp: longint;         { 256-byte temp for copy() result }
  needsCopyTemp: boolean;        { whether copy temp was allocated }
  concatPieces: longint;         { compile-time count of saved concat pieces }
  addrConcatScratch: longint;    { data segment addr of 17-slot scratch array }
  concatScratchBase: longint;    { byte offset of the current nesting level }
  addrConcatTemp: longint;       { 256-byte temp string for concat result }
  needsConcatScratch: boolean;   { whether scratch was allocated }
  startNlocals: longint;         { extra locals for _start (0 or 1) }
  curStringTempIdx: longint;     { WASM local index for string temp in current func }
  curFuncNeedsStringTemp: boolean; { whether current func needs the string temp local }
  curCaseTempIdx: longint;       { WASM local index for case selector temp }
  curFuncNeedsCaseTemp: boolean;  { whether current func needs the case temp local }
  curFuncIsFunction: boolean;    { whether current func is a function (has return value) }
  curFuncReturnIdx: longint;     { WASM local index for return value in current func }
  curFuncRetStructured: boolean; { current function returns via a caller buffer }
  curFuncRetTyp: longint;
  curFuncRetSize: longint;
  curFuncRetStrMax: longint;
  stmtUsedResultBuf: boolean;   { a statement allocated a structured result buffer }
  stmtArenaBytes: longint;      { bytes taken from $sp that live until the statement ends }
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
  optAlign: longint;          (* ALIGN n, record field alignment in bytes (1,2,4,8), default 4 *)
  optDump: boolean;           (* -dump command-line flag *)
  optLevel: longint;          (* -O0/-O1, peephole on/off, and {$OPT+/-}; no-op unless PEEPHOLE compiled in *)
  optStackChecks: boolean;    (* S+/-, default true: stack overflow guard *)
  optProgress: boolean;       (* -progress command-line flag *)
  optVerbose: boolean;        (* -v command-line flag, emits Info: lines *)
  optDebug: boolean;          (* -debug command-line flag, emits Debug: lines *)

  (* Progress reporting state. optProgressTotal is the source line count
     the host passed after -progress; 0 selects stage-based reporting. *)
  optProgressTotal: longint;
  progressStep: longint;      (* lines between reports in line mode *)
  progressNextLine: longint;  (* next source line that triggers a report *)
  infoNum: string[11];        (* scratch for formatting Info: counts *)

  { Pending compiler directives }
  hasPendingImport: boolean;
  pendingImportMod: string[63];
  pendingImportName: string[63];
  hasPendingExport: boolean;
  pendingExportName: string[63];

  { Conditional compilation state }
  ifdefActive: array[0..MaxIfdefDepth-1] of boolean; { was the IF branch taken? }
  ifdefDepth: longint;                                { current nesting depth }
  definedSyms: array[0..MaxDefines-1] of string;      { conditional symbols }
  numDefined: longint;

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

{** Write s to stderr with no trailing newline.

  Host embeddings rely on stderr for diagnostics; all messages carry
  a tag prefix (Error:, Warning:, Info:, Debug:, Progress:) so hosts
  can parse them mechanically. The FPC and WASM/TP branches differ
  only in how the output file is referenced. }
{$IFDEF FPC}
procedure WriteError(s: string);
begin
  write(stderr, s);
end;

{** Write s to stderr followed by a newline. }
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

{** Report a fatal error at the current source position and halt(1).

  All compiler errors go through here. No recovery is attempted — the
  single-pass design halts on the first error to avoid cascading false
  positives. Format: "Error: line:col: msg", as specified by the
  Language Reference section "Compiler Diagnostics". }
procedure Error(msg: string);
var lineStr, colStr: string[11];
begin
  str(srcLine, lineStr);
  str(srcCol, colStr);
  WriteErrorLn('Error: ' + lineStr + ':' + colStr + ': ' + msg);
  halt(1);
end;

{** Report a non-fatal diagnostic at the current source position.

  Compilation continues and the exit status is unaffected. Format:
  "Warning: line:col: msg", as specified by the Language Reference
  section "Compiler Diagnostics". }
procedure Warning(msg: string);
var lineStr, colStr: string[11];
begin
  str(srcLine, lineStr);
  str(srcCol, colStr);
  WriteErrorLn('Warning: ' + lineStr + ':' + colStr + ': ' + msg);
end;

{** Report a "<what> expected" error at the current source position. }
procedure Expected(what: string);
begin
  Error(what + ' expected');
end;

{** Report an informational line. No source position applies. Format:
  "Info: msg". Only emitted under -v. }
procedure Info(msg: string);
begin
  if optVerbose then
    WriteErrorLn('Info: ' + msg);
end;

{** Report a compiler trace line. Format: "Debug: msg". Only emitted
  under -debug.

  Distinct from -dump, which prints a human-readable disassembly of the
  finished module. Debug lines trace decisions as the single pass makes
  them, so they interleave with the source being read and show what the
  compiler did where. }
procedure Debug(msg: string);
begin
  if optDebug then
    WriteErrorLn('Debug: ' + msg);
end;

{** Report a trace line carrying the current source position, formatted
  the same way Error and Warning format theirs. }
procedure DebugAt(msg: string);
var lineStr, colStr: string[11];
begin
  if optDebug then begin
    str(srcLine, lineStr);
    str(srcCol, colStr);
    WriteErrorLn('Debug: ' + lineStr + ':' + colStr + ': ' + msg);
  end;
end;

{** Name of a symbol kind, for trace output.

  An out parameter rather than a string result: cpas does not support
  string-valued functions, and this unit must compile with itself. }
procedure SymKindStr(kind: longint; var res: string);
begin
  case kind of
    skConst: res := 'const';
    skVar:   res := 'var';
    skType:  res := 'type';
    skProc:  res := 'procedure';
    skFunc:  res := 'function';
    skField: res := 'field';
  else
    res := 'symbol';
  end;
end;

{** Emit one "Progress: done/total [msg]" line.

  Both counts are integers so a host can compute a percentage without
  parsing free text. done is clamped to total: a host that passes a line
  count lower than the real one would otherwise drive a progress bar
  past 100%. }
procedure ProgressReport(done, total: longint; msg: string);
var doneStr, totalStr: string[11];
begin
  if done > total then
    done := total;
  str(done, doneStr);
  str(total, totalStr);
  if msg = '' then
    WriteErrorLn('Progress: ' + doneStr + '/' + totalStr)
  else
    WriteErrorLn('Progress: ' + doneStr + '/' + totalStr + ' ' + msg);
end;

{** Report completion of compilation stage n (stage mode only).

  Stage mode is what -progress gives with no line count. The stages are
  coarse and parsing dominates the run, so the bar sits at 1/9 for most
  of a large compile. A host that knows the source size should pass it
  and get line-based reporting instead. }
procedure ProgressStage(n: longint; msg: string);
begin
  if optProgress and (optProgressTotal = 0) then
    ProgressReport(n, ProgressStages, msg);
end;

{** Report scanner position (line mode only). Called as each source line
  is completed. Reports at most ~100 times over the whole file so the
  cost stays negligible on the hot scanning path. }
procedure ProgressLine;
begin
  { Past the host's line count the ratio would be pinned at 1 and every
    further line would repeat the same output, so stop reporting and let
    the closing Done line finish the sequence. }
  if optProgress and (optProgressTotal > 0) and (srcLine >= progressNextLine)
      and (srcLine <= optProgressTotal) then begin
    ProgressReport(srcLine, optProgressTotal, '');
    progressNextLine := srcLine + progressStep;
  end;
end;

{** Convert an all-digits command-line argument to a positive integer.
  Returns 0 if s is empty or holds anything other than digits, which the
  caller treats as "not a count". }
function ArgToInt(s: string): longint;
var i, n: longint;
begin
  n := 0;
  if length(s) = 0 then begin
    ArgToInt := 0;
    exit;
  end;
  for i := 1 to length(s) do begin
    if not (s[i] in ['0'..'9']) then begin
      ArgToInt := 0;
      exit;
    end;
    n := n * 10 + (ord(s[i]) - ord('0'));
  end;
  ArgToInt := n;
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
      ProgressLine;
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
      ProgressLine;
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

{** Uppercase a string in place for case-insensitive IFDEF matching. }
procedure UpcaseStr(var s: string);
var
  i: longint;
  r: string;
  c: char;
begin
  r := '';
  for i := 1 to length(s) do begin
    c := s[i];
    if (c >= 'a') and (c <= 'z') then
      r := r + chr(ord(c) - 32)
    else
      r := r + c;
  end;
  s := r;
end;

{** Test whether a conditional symbol is currently defined.
  Caller must pass an already-uppercased name. }
function IsDefined(const name: string): boolean;
var
  i: longint;
begin
  for i := 0 to numDefined - 1 do
    if definedSyms[i] = name then begin
      IsDefined := true;
      exit;
    end;
  IsDefined := false;
end;

{** Add a conditional symbol; no-op if already defined.
  Caller must pass an already-uppercased name. }
procedure DefineSymbol(const name: string);
begin
  if IsDefined(name) then exit;
  if numDefined >= MaxDefines then
    Error('too many conditional symbols');
  definedSyms[numDefined] := name;
  inc(numDefined);
end;

{** Remove a conditional symbol; no-op if not defined.
  Caller must pass an already-uppercased name. }
procedure UndefSymbol(const name: string);
var
  i, j: longint;
begin
  for i := 0 to numDefined - 1 do
    if definedSyms[i] = name then begin
      for j := i to numDefined - 2 do
        definedSyms[j] := definedSyms[j + 1];
      dec(numDefined);
      exit;
    end;
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
    end else if (directive = 'S') or (directive = 'STACKCHECKS') then begin
      optStackChecks := ParseDirectiveSwitch;
    end else if (directive = 'R') or (directive = 'RANGECHECKS') then begin
      optRangeChecks := ParseDirectiveSwitch;
    end else if (directive = 'Q') or (directive = 'OVERFLOWCHECKS') then begin
      optOverflowChecks := ParseDirectiveSwitch;
    end else if directive = 'FILES' then begin
      { Filesystem access is opt-in, and the opt-in is visible in the module:
        asking for it adds path_open and fd_close to the import list, so a
        host can see from the imports alone whether a program wants files.

        It must be decided before any code is emitted, because helper
        function slots are numbered from the import count and those numbers
        are baked into call instructions as immediates. Requiring it before
        the program header makes that checkable rather than hoped for. }
      if ParseDirectiveSwitch then begin
        if emittedAnyCode then
          Error('FILES must be switched on before the program header');
        optFileIO := true;
      end else if optFileIO then
        Error('FILES cannot be switched off once on');
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
      intVal := ParseDirectiveInt;
      if (intVal <> 1) and (intVal <> 2) and (intVal <> 4) and (intVal <> 8) then
        Error('{$ALIGN} value must be 1, 2, 4, or 8');
      optAlign := intVal;
    end else if directive = 'OPT' then begin
      if ParseDirectiveSwitch then optLevel := 1 else optLevel := 0;
    end else if (directive = 'DEFINE') or (directive = 'UNDEF') then begin
      SkipDirectiveSpaces;
      symName := '';
      while (not atEof) and (ch <> '}') and (ch > ' ') do begin
        if ch in ['a'..'z'] then
          symName := symName + chr(ord(ch) - 32)
        else
          symName := symName + ch;
        ReadCh;
      end;
      if symName = '' then
        Error('{$' + directive + '} requires a symbol name');
      if directive = 'DEFINE' then
        DefineSymbol(symName)
      else
        UndefSymbol(symName);
      while (not atEof) and (ch <> '}') do ReadCh;
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
        condTrue := IsDefined(symName)
      else
        condTrue := not IsDefined(symName);
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
    end else if directive = 'MODE' then begin
      { fpc dialect selector. The compiler's own source carries a MODE TP
        directive for the bootstrap build; cpas has one dialect, so accept
        and ignore it rather than warning on every self-compile. }
      while (not atEof) and (ch <> '}') do
        ReadCh;
    end else begin
      { Unknown directive. Skipping it silently turns a typo such as
        RANGECHEKS into a directive that quietly does nothing, so say
        something and carry on. }
      Warning('unknown compiler directive: ' + directive);
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

function PeekNextToken: longint;
{** Peek at the next token without consuming it. Returns the token kind. }
var
  savedKind: longint;
  savedInt: longint;
  savedStr: string;
begin
  savedKind := tokKind;
  savedInt := tokInt;
  savedStr := tokStr;
  NextToken;
  PeekNextToken := tokKind;
  { Push back the peeked token }
  pendingTok := true;
  pendingKind := tokKind;
  pendingInt := tokInt;
  pendingStr := tokStr;
  { Restore the current token state }
  tokKind := savedKind;
  tokInt := savedInt;
  tokStr := savedStr;
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

{** Reset a small section buffer to empty. }
procedure SmallBufInit(var b: TSmallBuf);
begin
  b.len := 0;
end;

{** Reset a code-section buffer to empty. }
procedure CodeBufInit(var b: TCodeBuf);
begin
  b.len := 0;
  b.lastOpStart := -1;
  b.prevOpStart := -1;
end;

{** Reset a data-section buffer to empty. }
procedure DataBufInit(var b: TDataBuf);
begin
  b.len := 0;
end;

{** Append one byte to a small buffer. Halts on overflow. }
procedure SmallBufEmit(var b: TSmallBuf; v: byte);
begin
  if b.len > SmallBufMax then
    Error('section buffer overflow');
  b.data[b.len] := v;
  b.len := b.len + 1;
end;

{** Append one byte to the code buffer. Halts on overflow. }
procedure CodeBufEmit(var b: TCodeBuf; v: byte);
begin
  if b.len > CodeBufMax then
    Error('code buffer overflow');
  b.data[b.len] := v;
  b.len := b.len + 1;
end;

{** Append one byte to the data buffer. Halts on overflow. }
procedure DataBufEmit(var b: TDataBuf; v: byte);
begin
  if b.len > DataBufMax then
    Error('data buffer overflow');
  b.data[b.len] := v;
  b.len := b.len + 1;
end;

{ ---- LEB128 encoding ---- }

{** Emit an unsigned LEB128-encoded integer to the code buffer.

  LEB128 is WASM's variable-length integer encoding: 7 data bits per
  byte, high bit set on all but the last byte. Used for indices,
  offsets, alignment, and sizes in the WASM binary format. }
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

{** Emit a signed LEB128-encoded integer to the code buffer.

  Signed LEB128 uses sign-magnitude continuation: the loop stops when
  the remaining value is 0 (positive) or -1 (negative) AND the sign
  bit of the last emitted byte matches. TP shr is logical, so we
  manually sign-extend after the shift for negative values. Used for
  i32.const operands in WASM. }
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

{** Emit a signed LEB128 integer to a small buffer. See EmitSLEB128Fix. }
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

{** Emit an unsigned LEB128 integer to a small buffer. See EmitULEB128. }
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

{** Intern a WASM function signature and return its type-section index.

  Deduplicates: if a type with identical params and results already
  exists in wasmTypes, return its index; otherwise append. np/nr are
  the parameter and result counts, p/r the corresponding arrays. }
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

{** Return the index of the () -> () signature, interning on first use. }
function TypeVoidVoid: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  TypeVoidVoid := AddWasmType(0, p, 0, r);
end;

{** Return the index of the (i32) -> () signature. }
function TypeI32Void: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32;
  TypeI32Void := AddWasmType(1, p, 0, r);
end;

{** Return the index of the () -> (i32) signature. }
function TypeVoidI32: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  r[0] := WasmI32;
  TypeVoidI32 := AddWasmType(0, p, 1, r);
end;

{** Return the index of the (i32) -> (i32) signature. }
function TypeI32I32: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32;
  r[0] := WasmI32;
  TypeI32I32 := AddWasmType(1, p, 1, r);
end;

{** Return the index of the (i32, i32) -> () signature. }
function TypeI32x2Void: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32;
  TypeI32x2Void := AddWasmType(2, p, 0, r);
end;

{** Return the index of the (i32, i32) -> (i32) signature. }
function TypeI32x2I32: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32;
  r[0] := WasmI32;
  TypeI32x2I32 := AddWasmType(2, p, 1, r);
end;

{** Return the index of the (i32, i32, i32) -> () signature. }
function TypeI32x3Void: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32; p[2] := WasmI32;
  TypeI32x3Void := AddWasmType(3, p, 0, r);
end;

{** Return the index of the (i32, i32, i32) -> (i32) signature. }
function TypeI32x3I32: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32; p[2] := WasmI32;
  r[0] := WasmI32;
  TypeI32x3I32 := AddWasmType(3, p, 1, r);
end;

{** Return the index of the (i32 x4) -> () signature. }
function TypeI32x4Void: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32; p[2] := WasmI32; p[3] := WasmI32;
  TypeI32x4Void := AddWasmType(4, p, 0, r);
end;

{** Return the index of the (i32 x4) -> (i32) signature. }
function TypeI32x4I32: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32; p[2] := WasmI32; p[3] := WasmI32;
  r[0] := WasmI32;
  TypeI32x4I32 := AddWasmType(4, p, 1, r);
end;

{** Return the index of WASI path_open's signature:
  (fd, dirflags, path, path_len, oflags, rights: i64, inheriting: i64,
   fdflags, opened_fd_ptr) -> errno.

  The two i64 parameters are the only place the compiler emits a 64-bit
  value. It emits -1 for both, meaning "every right", and lets the host
  narrow that to what the preopened directory actually allows. That keeps
  64-bit support down to a single one-byte constant: SLEB128 of -1 is 0x7F. }
function TypePathOpen: longint;
var p: TWasmParamArr; r: TWasmResultArr;
begin
  p[0] := WasmI32; p[1] := WasmI32; p[2] := WasmI32; p[3] := WasmI32;
  p[4] := WasmI32; p[5] := WasmI64; p[6] := WasmI64; p[7] := WasmI32;
  p[8] := WasmI32;
  r[0] := WasmI32;
  TypePathOpen := AddWasmType(9, p, 1, r);
end;

{ ---- Import management ---- }

{** Register a WASM function import and return its function index.

  Imports occupy function indices 0..numImports-1 in the shared
  function index space; defined functions follow. Dedupes against
  existing imports on (modname, fieldname). All WASI imports are
  registered up front so numImports is stable before codegen. }
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

{** Return the function index of the WASI proc_exit import. }
function EnsureProcExit: longint;
begin
  EnsureProcExit := idxProcExit;
end;

{** Return the function index of the WASI fd_write import. }
function EnsureFdWrite: longint;
begin
  EnsureFdWrite := idxFdWrite;
end;

{ ---- Data segment management ---- }

{** Reserve size bytes in the data segment and return the starting address. }
function AllocData(size: longint): longint;
begin
  AllocData := dataPos;
  dataPos := dataPos + size;
end;

{** Reserve size bytes in the data segment at a boundary that is a multiple
  of align, emitting zero padding as needed. Returns the aligned address. }
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

{** Emit the raw bytes of s to the data segment (no length prefix).
  Returns the starting address. Used for WASI filenames, static
  literals used by helpers, etc. }
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

procedure EmitDataI32Bytes(v: longint);
{** Emit 4 little-endian bytes of v to the data buffer. Caller must have
  reserved space via AllocData / AllocDataAligned. }
begin
  DataBufEmit(secData, byte(v and $FF));
  DataBufEmit(secData, byte((v shr 8) and $FF));
  DataBufEmit(secData, byte((v shr 16) and $FF));
  DataBufEmit(secData, byte((v shr 24) and $FF));
end;

{** Lazily allocate the shared iovec, nwritten, and newline buffers in
  the data segment on first use. Subsequent calls are no-ops. }
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

{ ---- Peephole optimizer (optional, gated by the PEEPHOLE symbol) ---- }

{$IFDEF PEEPHOLE}
{** Decode a ULEB128 starting at position `pos` in `buf`. Returns the decoded
  value and advances `pos` past the encoded bytes. Mirrors EmitULEB128 but
  for in-buffer reads — used to compare operands of adjacent instructions
  when matching peephole patterns over `local.set X / local.get X`. }
function DecodeULEB128At(const b: TCodeBuf; var pos: longint): longint;
var result, shift: longint;
    byteVal: longint;
begin
  result := 0;
  shift := 0;
  repeat
    byteVal := b.data[pos];
    pos := pos + 1;
    result := result or ((byteVal and $7F) shl shift);
    shift := shift + 7;
  until (byteVal and $80) = 0;
  DecodeULEB128At := result;
end;

{** Attempt to rewrite the two trailing instructions in `b` into a shorter
  equivalent. Called from the bundled Emit* helpers after a complete
  instruction has been appended. `start` is the offset in `b.data` at which
  the just-emitted instruction begins (its opcode byte).

  Returns true if a rewrite fired, in which case the caller must not update
  the peephole window state (this routine already did). Returns false if
  no pattern matched; the caller then shifts prevOpStart/lastOpStart
  normally.

  Invariants preserved: b.len points past the final emitted byte, and at
  least one of lastOpStart/prevOpStart is reset to -1 after a rewrite so we
  don't try to peephole backwards across the rewritten region. }
function TryPeephole(var b: TCodeBuf; start: longint): boolean;
var prevOp, currOp: byte;
    prevPos, currPos: longint;
    prevIdx, currIdx: longint;
begin
  TryPeephole := false;
  if b.lastOpStart < 0 then exit;

  prevOp := b.data[b.lastOpStart];
  currOp := b.data[start];

  { Pattern: local.set X / local.get X  ->  local.tee X
    Rewrite by overwriting the set opcode with tee and truncating the
    trailing local.get (opcode + ULEB128). The existing ULEB128 for the
    set's operand becomes the tee's operand — it is the same index by
    construction. }
  if (prevOp = OpLocalSet) and (currOp = OpLocalGet) then begin
    prevPos := b.lastOpStart + 1;
    currPos := start + 1;
    prevIdx := DecodeULEB128At(b, prevPos);
    currIdx := DecodeULEB128At(b, currPos);
    if prevIdx = currIdx then begin
      b.data[b.lastOpStart] := OpLocalTee;
      b.len := start;
      { lastOpStart still marks the tee; drop prev context since the
        instruction that preceded set is no longer the immediate
        predecessor of anything we will match next. }
      b.prevOpStart := -1;
      TryPeephole := true;
      exit;
    end;
  end;

  { Pattern: i32.eqz / i32.eqz  ->  (remove both)
    Two successive eqz on a boolean are identity; truncate both. }
  if (prevOp = OpI32Eqz) and (currOp = OpI32Eqz) then begin
    b.len := b.lastOpStart;
    b.lastOpStart := -1;
    b.prevOpStart := -1;
    TryPeephole := true;
    exit;
  end;
end;
{$ENDIF}

{** Commit the instruction that begins at `start` to the peephole window.
  If PEEPHOLE is not compiled in, this is a no-op. If PEEPHOLE is compiled
  in but optLevel = 0 (e.g., -O0 or the OPT- directive), the window is still
  tracked but no rewrites fire — this keeps the state fresh for when OPT+
  later re-enables rewrites. }
procedure FinishOp(var b: TCodeBuf; start: longint);
{$IFDEF PEEPHOLE}
var fired: boolean;
{$ENDIF}
begin
  {$IFDEF PEEPHOLE}
  fired := false;
  if optLevel > 0 then fired := TryPeephole(b, start);
  if not fired then begin
    b.prevOpStart := b.lastOpStart;
    b.lastOpStart := start;
  end;
  {$ENDIF}
end;

{** Invalidate the peephole window. Called by emit paths that do not
  participate in peephole patterns (control flow, calls, memory ops) — they
  must not leave a stale "previous instruction" pointer that a later
  peephole attempt would match against across the intervening op. No-op
  when PEEPHOLE is not compiled in. }
procedure InvalidateOp(var b: TCodeBuf);
begin
  {$IFDEF PEEPHOLE}
  b.lastOpStart := -1;
  b.prevOpStart := -1;
  {$ENDIF}
end;

{ ---- Code emission helpers (emit to startCode buffer) ---- }

{** Emit a single WASM opcode byte to startCode.
  Participates in peephole only for opcodes that are safe stack ops with
  no operands (currently just i32.eqz). All other opcodes — control flow,
  arithmetic that we do not yet fold, end-of-block, etc. — invalidate the
  window so a later match does not cross this boundary. }
procedure EmitOp(op: byte);
{$IFDEF PEEPHOLE}
var start: longint;
{$ENDIF}
begin
  {$IFDEF PEEPHOLE}
  start := startCode.len;
  {$ENDIF}
  CodeBufEmit(startCode, op);
  {$IFDEF PEEPHOLE}
  if op = OpI32Eqz then
    FinishOp(startCode, start)
  else
    InvalidateOp(startCode);
  {$ENDIF}
end;

{** Emit local.get <idx> as a complete instruction.
  ;; WAT: local.get <idx> }
procedure EmitLocalGet(idx: longint);
var start: longint;
begin
  start := startCode.len;
  CodeBufEmit(startCode, OpLocalGet);
  EmitULEB128(startCode, idx);
  FinishOp(startCode, start);
end;

{** Emit local.set <idx> as a complete instruction.
  ;; WAT: local.set <idx> }
procedure EmitLocalSet(idx: longint);
var start: longint;
begin
  start := startCode.len;
  CodeBufEmit(startCode, OpLocalSet);
  EmitULEB128(startCode, idx);
  FinishOp(startCode, start);
end;

{** Emit local.tee <idx> as a complete instruction.
  ;; WAT: local.tee <idx> }
procedure EmitLocalTee(idx: longint);
var start: longint;
begin
  start := startCode.len;
  CodeBufEmit(startCode, OpLocalTee);
  EmitULEB128(startCode, idx);
  FinishOp(startCode, start);
end;

{** Emit global.get <idx> as a complete instruction.
  ;; WAT: global.get <idx> }
procedure EmitGlobalGet(idx: longint);
var start: longint;
begin
  start := startCode.len;
  CodeBufEmit(startCode, OpGlobalGet);
  EmitULEB128(startCode, idx);
  FinishOp(startCode, start);
end;

{** Emit global.set <idx> as a complete instruction.
  ;; WAT: global.set <idx> }
procedure EmitGlobalSet(idx: longint);
var start: longint;
begin
  start := startCode.len;
  CodeBufEmit(startCode, OpGlobalSet);
  EmitULEB128(startCode, idx);
  FinishOp(startCode, start);
end;

{** Emit i32.const with signed LEB128 operand.
  ;; WAT: i32.const <value> }
procedure EmitI32Const(value: longint);
begin
  CodeBufEmit(startCode, OpI32Const);
  EmitSLEB128Fix(startCode, value);
  InvalidateOp(startCode);
end;

{** Emit call to a WASM function by index.
  ;; WAT: call <funcIdx> }
procedure EmitCall(funcIdx: longint);
begin
  CodeBufEmit(startCode, OpCall);
  EmitULEB128(startCode, funcIdx);
  InvalidateOp(startCode);
end;

{** Emit i32.store with memarg (align exponent, offset).
  ;; WAT: i32.store offset=<offset> align=<1 shl align> }
procedure EmitI32Store(align, offset: longint);
begin
  CodeBufEmit(startCode, OpI32Store);
  EmitULEB128(startCode, align);
  EmitULEB128(startCode, offset);
  InvalidateOp(startCode);
end;

{** Emit i32.store8 (byte store) at given offset, natural alignment.
  ;; WAT: i32.store8 offset=<offset> }
procedure EmitI32Store8(offset: longint);
begin
  CodeBufEmit(startCode, OpI32Store8);
  EmitULEB128(startCode, 0);
  EmitULEB128(startCode, offset);
  InvalidateOp(startCode);
end;

{** Emit a store sized by type: i32.store8 for char/boolean, i32.store
  (aligned) for integer and other 4-byte types. Stack: addr, value. }
procedure EmitStoreByType(typ: longint);
begin
  if (typ = tyChar) or (typ = tyBoolean) then
    EmitI32Store8(0)
  else
    EmitI32Store(2, 0);
end;

{** Emit the bulk-memory memory.copy instruction.
  Stack: dst, src, len. ;; WAT: memory.copy }
procedure EmitMemoryCopy;
begin
  CodeBufEmit(startCode, $FC);
  CodeBufEmit(startCode, $0A);
  CodeBufEmit(startCode, $00);
  CodeBufEmit(startCode, $00);
  InvalidateOp(startCode);
end;

{** Emit i32.load with memarg.
  ;; WAT: i32.load offset=<offset> align=<1 shl align> }
procedure EmitI32Load(align, offset: longint);
begin
  CodeBufEmit(startCode, OpI32Load);
  EmitULEB128(startCode, align);
  EmitULEB128(startCode, offset);
  InvalidateOp(startCode);
end;

{** Emit i32.load8_u (zero-extend byte load).
  ;; WAT: i32.load8_u offset=<offset> }
procedure EmitI32Load8u(align, offset: longint);
begin
  CodeBufEmit(startCode, OpI32Load8u);
  EmitULEB128(startCode, align);
  EmitULEB128(startCode, offset);
  InvalidateOp(startCode);
end;

{ ---- Symbol table ---- }

{** Reset the symbol table and scope stack to empty. }
procedure InitSymTable;
begin
  numSyms := 0;
  scopeDepth := 0;
  scopeBase[0] := 0;
end;

{** Push a new lexical scope onto the scope stack.

  The symbol table is a single flat array; scopeBase[d] records the
  first index belonging to scope depth d. EnterScope captures the
  current numSyms as the boundary, so LeaveScope can truncate the
  array back to that point in O(1) when the scope ends. This mirrors
  the classic TP compiler technique: no dynamic allocation, and
  symbol lookup walks backward (most-local first) for Pascal-correct
  shadowing. }
procedure EnterScope;
var dbgScope: string[11];
begin
  scopeDepth := scopeDepth + 1;
  if scopeDepth >= MaxScopes then
    Error('scope nesting too deep');
  scopeBase[scopeDepth] := numSyms;
  if optDebug then begin
    str(scopeDepth, dbgScope);
    DebugAt('enter scope ' + dbgScope);
  end;
end;

{** Pop the current scope, discarding all symbols added since
  EnterScope. O(1) — just rewinds numSyms to the saved boundary. }
procedure LeaveScope;
var dbgScope, dbgCount: string[11];
begin
  if optDebug then begin
    str(scopeDepth, dbgScope);
    str(numSyms - scopeBase[scopeDepth], dbgCount);
    DebugAt('leave scope ' + dbgScope + ', discarding ' + dbgCount + ' symbols');
  end;
  numSyms := scopeBase[scopeDepth];
  scopeDepth := scopeDepth - 1;
end;

{** Look up name in the symbol table, returning its index or -1.

  Walks backward so inner-scope symbols shadow outer-scope ones
  with the same name. Linear search — adequate for expected symbol
  counts (hundreds, not thousands) per PLAN.md. }
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

{** Add a symbol to the current scope and return its index.

  Initializes the symbol with kind/typ and sensible defaults for the
  remaining fields (typeIdx, offset, size, strMax, VAR/CONST param
  flags). Halts on overflow. }
function AddSym(const name: string; kind, typ: longint): longint;
var
  dbgKind: string;
  dbgScope, dbgLevel: string[11];
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
  if optDebug then begin
    SymKindStr(kind, dbgKind);
    if scopeDepth = 0 then
      { Scope 0 holds the predefined types and constants. No source
        position applies: nothing has been read yet. }
      Debug('built-in ' + dbgKind + ' ' + name)
    else begin
      str(scopeDepth, dbgScope);
      str(curNestLevel, dbgLevel);
      DebugAt('declare ' + dbgKind + ' ' + name +
              ' at scope ' + dbgScope + ', level ' + dbgLevel);
    end;
  end;
end;

{** Populate the outermost scope with built-in types and constants
  (INTEGER, BOOLEAN, CHAR, BYTE, WORD, SHORTINT, LONGINT, TRUE, FALSE,
  MAXINT). Must be called after InitSymTable before any user code. }
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

function IsStructuredRet(t: longint): boolean;
{** Whether a return type is passed through a caller-allocated buffer rather
  than on the WASM operand stack, which can only carry an i32. }
begin
  IsStructuredRet := (t = tyString) or (t = tyRecord) or (t = tyArray);
end;

function FindOrAddPointerType(targetTyp, targetTypeIdx, targetSize, targetStrMax: longint): longint;
{** Return a descriptor for ^Target, reusing an existing one when the target
  matches. The target is held in the elem* fields, the same slots an array
  uses for its element type. Reuse keeps a program with many pointers to the
  same type from exhausting the 256-entry table, and it is safe because two
  pointer types with the same target are the same type.

  Descriptors still awaiting a forward reference (elemType = tyNone) are never
  matched: their target is not known yet, so they cannot be compared. }
var i, idx: longint;
begin
  for i := 0 to numTypes - 1 do
    if (types[i].kind = tyPointer) and (types[i].elemType <> tyNone)
       and (types[i].elemType = targetTyp)
       and (types[i].elemTypeIdx = targetTypeIdx)
       and (types[i].elemStrMax = targetStrMax) then begin
      FindOrAddPointerType := i;
      exit;
    end;
  idx := AddTypeDesc;
  types[idx].kind := tyPointer;
  types[idx].size := 4;
  types[idx].elemType := targetTyp;
  types[idx].elemTypeIdx := targetTypeIdx;
  types[idx].elemSize := targetSize;
  types[idx].elemStrMax := targetStrMax;
  FindOrAddPointerType := idx;
end;

function PointerTargetsMatch(aIdx, bIdx: longint): boolean;
{** Whether two pointer types may be assigned or compared. A descriptor index
  of -1 is nil, which is compatible with every pointer type. Otherwise the
  targets must agree; the descriptor indices need not, since a forward
  reference and a later direct reference can produce two descriptors for the
  same pointer type. }
begin
  if (aIdx < 0) or (bIdx < 0) then
    PointerTargetsMatch := true
  else
    PointerTargetsMatch := (types[aIdx].elemType = types[bIdx].elemType)
                       and (types[aIdx].elemTypeIdx = types[bIdx].elemTypeIdx);
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
  fields[numFields].variantId := 0;
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

procedure ParseSubrangeLiteral(var outLo, outHi, outBaseTyp, outBaseTypeIdx: longint);
{** Parse `Constant '..' Constant`. Base type is inferred from the low bound.
    For enum constants, outBaseTypeIdx is set to the enum's type descriptor so
    callers can identify which enum the bounds belong to; otherwise -1. }
var
  hiTyp, sym, hiTypeIdx: longint;
begin
  outBaseTypeIdx := -1;
  hiTypeIdx := -1;
  { Snoop a leading identifier: if it's a named enum constant, record its
    enum type descriptor. EvalConstExpr would otherwise lose this info. }
  if tokKind = tkIdent then begin
    sym := LookupSym(tokStr);
    if (sym >= 0) and (syms[sym].kind = skConst) and (syms[sym].typ = tyEnum) then
      outBaseTypeIdx := syms[sym].typeIdx;
  end;
  EvalConstExpr(outLo, outBaseTyp);
  if not (outBaseTyp in [tyInteger, tyChar, tyBoolean, tyEnum]) then
    Error('ordinal type expected for subrange bound');
  if tokKind <> tkDotDot then Expected('..');
  NextToken;
  { Snoop the high-bound enum, same trick. }
  if tokKind = tkIdent then begin
    sym := LookupSym(tokStr);
    if (sym >= 0) and (syms[sym].kind = skConst) and (syms[sym].typ = tyEnum) then
      hiTypeIdx := syms[sym].typeIdx;
  end;
  EvalConstExpr(outHi, hiTyp);
  if hiTyp <> outBaseTyp then
    Error('subrange bounds must have the same ordinal type');
  if (outBaseTyp = tyEnum) and (outBaseTypeIdx <> hiTypeIdx) then
    Error('subrange bounds must belong to the same enum type');
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
  loBound, hiBound, scratchTypeIdx: longint;
  ptrTargetSize, ptrTargetStrMax: longint;
  { Variant record fields }
  tagFieldName: string;
  tagFieldTyp, tagFieldTypeIdx, tagFieldSize, tagFieldStrMax: longint;
  tagOfs: longint;
  variantId: longint;
  maxVariantSize: longint;
  lo, hi: longint;
  constListOfs: longint;
  variantFieldOfs: longint;
  fldIdx: longint;
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
  end else if tokKind = tkCaret then begin
    { Pointer type: ^TypeIdentifier. The grammar allows only a name here, not
      an anonymous record or array, which is what makes the forward reference
      below tractable in a single pass. }
    NextToken;
    if tokKind <> tkIdent then
      Expected('type name after ''^''');
    typeName := tokStr;
    typId := LookupSym(typeName);
    outTyp := tyPointer;
    outSize := 4;
    if (typId >= 0) and (syms[typId].kind = skType) then begin
      if syms[typId].typ = tyString then begin
        ptrTargetStrMax := syms[typId].strMax;
        if ptrTargetStrMax = 0 then ptrTargetStrMax := 255;
        ptrTargetSize := ptrTargetStrMax + 1;
      end else if (syms[typId].typ = tyRecord) or (syms[typId].typ = tyArray)
                  or (syms[typId].typ = tySet) then begin
        ptrTargetStrMax := 0;
        ptrTargetSize := types[syms[typId].typeIdx].size;
      end else begin
        ptrTargetStrMax := 0;
        ptrTargetSize := 4;
      end;
      outTypeIdx := FindOrAddPointerType(syms[typId].typ, syms[typId].typeIdx,
                                         ptrTargetSize, ptrTargetStrMax);
    end else if typId >= 0 then
      Error(typeName + ' is not a type')
    else begin
      { Forward reference. Park a descriptor with no target and record the
        name; ResolvePendingPointers fills it in at the end of the block. }
      if numPendingPtr >= MaxPendingPtr then
        Error('too many unresolved forward pointer types');
      outTypeIdx := AddTypeDesc;
      types[outTypeIdx].kind := tyPointer;
      types[outTypeIdx].size := 4;
      pendingPtrType[numPendingPtr] := outTypeIdx;
      pendingPtrName[numPendingPtr] := typeName;
      pendingPtrLine[numPendingPtr] := srcLine;
      numPendingPtr := numPendingPtr + 1;
    end;
    NextToken;
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
    { Record type (possibly with variant part) }
    NextToken;
    tIdx := AddTypeDesc;
    types[tIdx].kind := tyRecord;
    types[tIdx].fieldStart := numFields;
    types[tIdx].fieldCount := 0;
    types[tIdx].variantOfs := -1;
    fieldOfs := 0;

    { Parse fixed fields }
    while (tokKind <> tkEnd) and (tokKind <> tkCase) and (tokKind <> tkEOF) do begin
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
        { Align to optAlign boundary (1, 2, 4, or 8 from ALIGN directive) }
        pad := (optAlign - (fieldOfs mod optAlign)) mod optAlign;
        fieldOfs := fieldOfs + pad;
        AddField(fieldNames[fi], fieldTyp, fieldTypeIdx, fieldOfs, fieldSize, fieldStrMax);
        types[tIdx].fieldCount := types[tIdx].fieldCount + 1;
        fieldOfs := fieldOfs + fieldSize;
      end;

      if tokKind = tkSemicolon then
        NextToken;
    end;

    { Parse variant part if present }
    if tokKind = tkCase then begin
      types[tIdx].variantOfs := fieldOfs;
      NextToken;

      { Parse tag field name or type }
      tagFieldName := '';
      if tokKind = tkIdent then begin
        { Check if this is a field name (followed by :) or type name (followed by of/int const) }
        if PeekNextToken = tkColon then begin
          { Named tag: identifier : type }
          tagFieldName := tokStr;
          NextToken;
          NextToken;  { consume : }
          ParseTypeSpec(tagFieldTyp, tagFieldTypeIdx, tagFieldSize, tagFieldStrMax);
          { Align tag field }
          pad := (optAlign - (fieldOfs mod optAlign)) mod optAlign;
          fieldOfs := fieldOfs + pad;
          tagOfs := fieldOfs;
          AddField(tagFieldName, tagFieldTyp, tagFieldTypeIdx, tagOfs, tagFieldSize, tagFieldStrMax);
          types[tIdx].fieldCount := types[tIdx].fieldCount + 1;
          fieldOfs := fieldOfs + tagFieldSize;
        end else begin
          { Unnamed tag: type name directly }
          ParseTypeSpec(tagFieldTyp, tagFieldTypeIdx, tagFieldSize, tagFieldStrMax);
          { Align tag field }
          pad := (optAlign - (fieldOfs mod optAlign)) mod optAlign;
          fieldOfs := fieldOfs + pad;
          tagOfs := fieldOfs;
          { Add as field with empty name to mark it as unnamed }
          AddField('', tagFieldTyp, tagFieldTypeIdx, tagOfs, tagFieldSize, tagFieldStrMax);
          types[tIdx].fieldCount := types[tIdx].fieldCount + 1;
          fieldOfs := fieldOfs + tagFieldSize;
        end;
      end else begin
        { Type follows directly (no identifier at all) }
        ParseTypeSpec(tagFieldTyp, tagFieldTypeIdx, tagFieldSize, tagFieldStrMax);
        { Align tag field }
        pad := (optAlign - (fieldOfs mod optAlign)) mod optAlign;
        fieldOfs := fieldOfs + pad;
        tagOfs := fieldOfs;
        { Add as field with empty name to mark it as unnamed }
        AddField('', tagFieldTyp, tagFieldTypeIdx, tagOfs, tagFieldSize, tagFieldStrMax);
        types[tIdx].fieldCount := types[tIdx].fieldCount + 1;
        fieldOfs := fieldOfs + tagFieldSize;
      end;

      Expect(tkOf);

      { variant offset where variants start }
      constListOfs := fieldOfs;
      maxVariantSize := 0;
      variantId := 1;

      { Parse each variant }
      repeat
        { Parse case labels (constants or ranges) }
        if tokKind = tkInteger then begin
          lo := tokInt;
          NextToken;
          if tokKind = tkDotDot then begin
            NextToken;
            if tokKind <> tkInteger then
              Error('integer constant expected for high bound');
            hi := tokInt;
            NextToken;
          end else
            hi := lo;
        end else
          Error('integer constant expected for variant label');

        { Parse any additional labels (separated by commas) }
        while tokKind = tkComma do begin
          NextToken;
          if tokKind = tkInteger then begin
            lo := tokInt;
            NextToken;
            if tokKind = tkDotDot then begin
              NextToken;
              if tokKind <> tkInteger then
                Error('integer constant expected for high bound');
              hi := tokInt;
              NextToken;
            end else
              hi := lo;
          end else
            Error('integer constant expected for variant label');
        end;

        Expect(tkColon);
        Expect(tkLParen);

        { Parse variant fields }
        variantFieldOfs := constListOfs;

        while (tokKind <> tkRParen) and (tokKind <> tkEOF) do begin
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
            break;

          Expect(tkColon);
          ParseTypeSpec(fieldTyp, fieldTypeIdx, fieldSize, fieldStrMax);

          for fi := 0 to nFieldNames - 1 do begin
            pad := (optAlign - (variantFieldOfs mod optAlign)) mod optAlign;
            variantFieldOfs := variantFieldOfs + pad;
            fldIdx := AddField(fieldNames[fi], fieldTyp, fieldTypeIdx, variantFieldOfs, fieldSize, fieldStrMax);
            fields[fldIdx].variantId := variantId;
            types[tIdx].fieldCount := types[tIdx].fieldCount + 1;
            variantFieldOfs := variantFieldOfs + fieldSize;
          end;

          if tokKind = tkSemicolon then
            NextToken;
        end;

        { Track maximum variant size }
        if variantFieldOfs - constListOfs > maxVariantSize then
          maxVariantSize := variantFieldOfs - constListOfs;

        Expect(tkRParen);

        variantId := variantId + 1;

        if tokKind = tkSemicolon then
          NextToken
        else
          break;
      until tokKind <> tkInteger;

      fieldOfs := constListOfs + maxVariantSize;
    end;

    Expect(tkEnd);

    { Final alignment — pad record size to current alignment boundary }
    pad := (optAlign - (fieldOfs mod optAlign)) mod optAlign;
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
    (* Set type: accepts three base forms —
         set of T             bare ordinal type (integer/char/boolean/enum)
         set of T(Lo..Hi)     named subrange rooted in an ordinal type T
         set of Lo..Hi        subrange literal (e.g. 0..63, 'a'..'z', Mon..Fri)
       The bitmap anchors at ordinal 0 regardless of arrLo. arrLo is still
       recorded so a future {$R+} pass can range-check membership tests. *)
    NextToken;
    Expect(tkOf);
    tIdx := AddTypeDesc;
    types[tIdx].kind := tySet;
    elemTypeIdx := -1;

    if tokKind = tkIdent then begin
      typId := LookupSym(tokStr);
      if typId < 0 then
        Error('unknown identifier: ' + tokStr);
      if syms[typId].kind = skType then begin
        elemTyp := syms[typId].typ;
        elemTypeIdx := syms[typId].typeIdx;
        if not (elemTyp in [tyInteger, tyChar, tyBoolean, tyEnum]) then
          Error('set base type must be ordinal');
        typeName := syms[typId].name;
        NextToken;
        if tokKind = tkLParen then begin
          { Named-subrange form: T(Lo..Hi) — T constrains the bound range. }
          NextToken;
          ParseSubrangeLiteral(loBound, hiBound, boundType, scratchTypeIdx);
          Expect(tkRParen);
          if elemTyp = tyEnum then begin
            if (loBound < types[elemTypeIdx].arrLo) or (hiBound > types[elemTypeIdx].arrHi) then
              Error('subrange out of range for ' + typeName);
          end else if elemTyp = tyChar then begin
            if (loBound < 0) or (hiBound > 255) then
              Error('char subrange bound out of range');
          end else if elemTyp = tyBoolean then begin
            if (loBound < 0) or (hiBound > 1) then
              Error('boolean subrange bound out of range');
          end;
          types[tIdx].arrLo := loBound;
          types[tIdx].arrHi := hiBound;
        end else begin
          { Bare type name — legacy defaults. }
          if elemTyp = tyInteger then begin
            types[tIdx].arrLo := 0;
            types[tIdx].arrHi := 31;
          end else if elemTyp = tyChar then begin
            types[tIdx].arrLo := 0;
            types[tIdx].arrHi := 255;
          end else if elemTyp = tyBoolean then begin
            types[tIdx].arrLo := 0;
            types[tIdx].arrHi := 1;
          end else if elemTyp = tyEnum then begin
            types[tIdx].arrLo := types[elemTypeIdx].arrLo;
            types[tIdx].arrHi := types[elemTypeIdx].arrHi;
          end;
        end;
      end else if syms[typId].kind = skConst then begin
        { Subrange literal starting with a named constant (e.g. Mon..Fri). }
        ParseSubrangeLiteral(loBound, hiBound, elemTyp, elemTypeIdx);
        types[tIdx].arrLo := loBound;
        types[tIdx].arrHi := hiBound;
      end else
        Error('set base type must be an ordinal type or subrange');
    end else begin
      { Subrange literal starting with a numeric/char/boolean literal. }
      ParseSubrangeLiteral(loBound, hiBound, elemTyp, elemTypeIdx);
      types[tIdx].arrLo := loBound;
      types[tIdx].arrHi := hiBound;
    end;

    { Validate. Bitmap is anchored at ordinal 0, so arrHi alone drives size. }
    if types[tIdx].arrLo < 0 then
      Error('set base type may not include negative values');
    if types[tIdx].arrHi < types[tIdx].arrLo then
      Error('set base type has inverted range');
    if types[tIdx].arrHi > 255 then
      Error('set base type too large (max 256 elements)');
    types[tIdx].elemType := elemTyp;
    types[tIdx].elemTypeIdx := elemTypeIdx;
    if types[tIdx].arrHi < 32 then
      types[tIdx].size := 4                           { fits in i32 }
    else
      types[tIdx].size := 32;                         { large set: fixed 256-bit bitmap }

    outTyp := tySet;
    outTypeIdx := tIdx;
    outSize := types[tIdx].size;
    outStrMax := 0;
  end else
    Error('type name expected');
end;

{ ---- Display and frame access ---- }

(** Push the frame pointer for a target nesting level onto the WASM stack.

  Compact Pascal uses the Dijkstra display technique for nested
  procedure access: WASM global 0 holds the current frame pointer
  ($sp), and globals 1..MaxNestLevel hold the frame pointers of
  enclosing procedures at each outer level (the "display"). When
  accessing a variable at the current level, load global 0; when
  accessing an outer-scope variable at level L, load display[L] =
  global L+1. This makes non-local access O(1) and avoids walking
  static links.

  ;; WAT: global.get $sp            (if level = curNestLevel)
  ;; WAT: global.get $display{level} (otherwise)
*)
procedure EmitStmtArenaRelease;
{** Return $sp to the frame base, dropping every structured result buffer and
  saved concat slot the current statement took.

  Emitted before exit, break, and continue, because each of those branches
  past the release the statement would otherwise have run. Two instructions,
  and it is not conditional on the statement having allocated anything: a
  branch can leave a statement whose allocation happened further out, and the
  compiler does not know that from where the branch is written. Restoring to
  the frame base is idempotent, so paying it always is simpler than being
  clever about when. }
begin
  EmitGlobalGet(curNestLevel + 1);  { display[curNestLevel] = frame base }
  EmitGlobalSet(0);
  stmtArenaBytes := 0;
end;

procedure EmitFramePtr(level: longint);
{** Push the base address of the frame at `level`.

  For the current level this reads $sp rather than the display global, which
  is a byte shorter and valid because $sp equals the frame base at every
  statement boundary. A structured function result breaks that: its buffer is
  taken from the stack and held until the statement ends, so $sp is below the
  frame base for the rest of the statement. Once one has been taken, read the
  display global instead. }
begin
  if (level = curNestLevel) and not stmtUsedResultBuf then begin
    EmitGlobalGet(0);  { $sp }
  end else begin
    EmitGlobalGet(level + 1);  { display[level] = global level+1 }
  end;
end;

(** Push the pointer value held by a var- or const-parameter.

  var and const parameters are passed by address. The caller stores
  the target's address in the callee's frame at syms[sym].offset, so
  loading that slot yields the pointer, which can then be dereferenced
  by a subsequent load/store. Used whenever the callee wants to read
  or write through the parameter.

  ;; WAT: global.get $frame_ptr / i32.const <offset> / i32.add / i32.load
*)
procedure EmitVarParamPtr(sym: longint);
begin
  EmitFramePtr(syms[sym].level);
  EmitI32Const(syms[sym].offset);
  EmitOp(OpI32Add);
  EmitI32Load(2, 0);
end;

procedure EmitPointerVarAddr(sym: longint);
{** Push the address of a pointer variable, so a caller can load or store the
  pointer itself rather than what it points at. Used by new and dispose,
  which both write back to the variable. }
begin
  if syms[sym].isVarParam then
    EmitVarParamPtr(sym)
  else begin
    EmitFramePtr(syms[sym].level);
    EmitI32Const(syms[sym].offset);
    EmitOp(OpI32Add);
  end;
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

{** Write bytes to stdout (fd 1) via fd_write. }
procedure EmitWriteString(addr, len: longint);
begin
  EmitWriteStringFd(1, addr, len);
end;

{** Write a single newline character to the given file descriptor. }
procedure EmitWriteNewlineFd(fd: longint);
begin
  EnsureIOBuffers;
  EmitWriteStringFd(fd, addrNewline, 1);
end;

{** Write a single newline character to stdout. }
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
    { 17 slots x 4 bytes per nesting level: 16 concat pieces, plus one for
      the final piece when writing a concatenation to stderr (see
      ParseWriteArgs). Four levels, because a concatenation whose operand is
      a call whose argument is another concatenation needs its own slots;
      concatScratchBase selects the level. }
    addrConcatScratch := AllocDataAligned(ConcatScratchBytes, 4);
    for j := 1 to ConcatScratchBytes do DataBufEmit(secData, 0);
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

procedure EnsureArgsInit;
{** Allocate argv storage and emit WASI init code prefixed to _start.
  Backs the ParamCount/ParamStr intrinsics. Init code calls
  args_sizes_get/args_get, then converts each C-string argv[i] to a
  Pascal short string in a fixed-size 256-byte slot. Uses _start
  locals 0..3 as scratch; user code overwrites these before reading. }
var
  j: longint;
begin
  if needsArgs then exit;
  needsArgs := true;

  addrArgc := AllocDataAligned(4, 4);
  for j := 1 to 4 do DataBufEmit(secData, 0);
  addrArgBufSize := AllocDataAligned(4, 4);
  for j := 1 to 4 do DataBufEmit(secData, 0);
  addrArgv := AllocDataAligned(MaxArgs * 4, 4);
  for j := 1 to MaxArgs * 4 do DataBufEmit(secData, 0);
  addrArgBuf := AllocDataAligned(ArgBufCap, 4);
  for j := 1 to ArgBufCap do DataBufEmit(secData, 0);
  addrArgSlots := AllocDataAligned(MaxArgs * ArgSlotSize, 4);
  for j := 1 to MaxArgs * ArgSlotSize do DataBufEmit(secData, 0);

  { args_sizes_get(addrArgc, addrArgBufSize); drop errno }
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, addrArgc);
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, addrArgBufSize);
  CodeBufEmit(argsInitCode, OpCall); EmitULEB128(argsInitCode, idxArgsSizesGet);
  CodeBufEmit(argsInitCode, OpDrop);

  { args_get(addrArgv, addrArgBuf); drop errno }
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, addrArgv);
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, addrArgBuf);
  CodeBufEmit(argsInitCode, OpCall); EmitULEB128(argsInitCode, idxArgsGet);
  CodeBufEmit(argsInitCode, OpDrop);

  { local 0 = min(argc, MaxArgs) via select(argc, MaxArgs, argc < MaxArgs) }
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, addrArgc);
  CodeBufEmit(argsInitCode, OpI32Load); EmitULEB128(argsInitCode, 2); EmitULEB128(argsInitCode, 0);
  CodeBufEmit(argsInitCode, OpLocalTee); EmitULEB128(argsInitCode, 0);
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, MaxArgs);
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 0);
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, MaxArgs);
  CodeBufEmit(argsInitCode, OpI32LtS);
  CodeBufEmit(argsInitCode, OpSelect);
  CodeBufEmit(argsInitCode, OpLocalSet); EmitULEB128(argsInitCode, 0);

  { local 1 = 0 (loop index i) }
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, 0);
  CodeBufEmit(argsInitCode, OpLocalSet); EmitULEB128(argsInitCode, 1);

  (* block { loop { ... br_if 1 to break; ...; br 0 } } *)
  CodeBufEmit(argsInitCode, OpBlock); CodeBufEmit(argsInitCode, WasmVoid);
  CodeBufEmit(argsInitCode, OpLoop); CodeBufEmit(argsInitCode, WasmVoid);

  { if i >= argc_clamped break }
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 1);
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 0);
  CodeBufEmit(argsInitCode, OpI32GeS);
  CodeBufEmit(argsInitCode, OpBrIf); EmitULEB128(argsInitCode, 1);

  { cstr = argv[i] = load(addrArgv + i*4); store in local 2 }
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, addrArgv);
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 1);
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, 2);
  CodeBufEmit(argsInitCode, OpI32Shl);
  CodeBufEmit(argsInitCode, OpI32Add);
  CodeBufEmit(argsInitCode, OpI32Load); EmitULEB128(argsInitCode, 2); EmitULEB128(argsInitCode, 0);
  CodeBufEmit(argsInitCode, OpLocalSet); EmitULEB128(argsInitCode, 2);

  { scan = cstr; store in local 3 }
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 2);
  CodeBufEmit(argsInitCode, OpLocalSet); EmitULEB128(argsInitCode, 3);

  (* block { loop { if *scan == 0 break; scan++; br 0 } } — strlen *)
  CodeBufEmit(argsInitCode, OpBlock); CodeBufEmit(argsInitCode, WasmVoid);
  CodeBufEmit(argsInitCode, OpLoop); CodeBufEmit(argsInitCode, WasmVoid);
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 3);
  CodeBufEmit(argsInitCode, OpI32Load8u); EmitULEB128(argsInitCode, 0); EmitULEB128(argsInitCode, 0);
  CodeBufEmit(argsInitCode, OpI32Eqz);
  CodeBufEmit(argsInitCode, OpBrIf); EmitULEB128(argsInitCode, 1);
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 3);
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, 1);
  CodeBufEmit(argsInitCode, OpI32Add);
  CodeBufEmit(argsInitCode, OpLocalSet); EmitULEB128(argsInitCode, 3);
  CodeBufEmit(argsInitCode, OpBr); EmitULEB128(argsInitCode, 0);
  CodeBufEmit(argsInitCode, OpEnd);
  CodeBufEmit(argsInitCode, OpEnd);

  { len = scan - cstr; store in local 3 }
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 3);
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 2);
  CodeBufEmit(argsInitCode, OpI32Sub);
  CodeBufEmit(argsInitCode, OpLocalSet); EmitULEB128(argsInitCode, 3);

  { if len > 255 then len := 255 }
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 3);
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, 255);
  CodeBufEmit(argsInitCode, OpI32GtU);
  CodeBufEmit(argsInitCode, OpIf); CodeBufEmit(argsInitCode, WasmVoid);
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, 255);
  CodeBufEmit(argsInitCode, OpLocalSet); EmitULEB128(argsInitCode, 3);
  CodeBufEmit(argsInitCode, OpEnd);

  { slot = addrArgSlots + i*256; store length byte at slot[0] }
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, addrArgSlots);
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 1);
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, 8);
  CodeBufEmit(argsInitCode, OpI32Shl);
  CodeBufEmit(argsInitCode, OpI32Add);
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 3);
  CodeBufEmit(argsInitCode, OpI32Store8); EmitULEB128(argsInitCode, 0); EmitULEB128(argsInitCode, 0);

  { memory.copy(slot+1, cstr, len) }
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, addrArgSlots + 1);
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 1);
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, 8);
  CodeBufEmit(argsInitCode, OpI32Shl);
  CodeBufEmit(argsInitCode, OpI32Add);
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 2);
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 3);
  CodeBufEmit(argsInitCode, $FC); CodeBufEmit(argsInitCode, $0A);
  CodeBufEmit(argsInitCode, $00); CodeBufEmit(argsInitCode, $00);

  { i++; continue loop }
  CodeBufEmit(argsInitCode, OpLocalGet); EmitULEB128(argsInitCode, 1);
  CodeBufEmit(argsInitCode, OpI32Const); EmitSLEB128Fix(argsInitCode, 1);
  CodeBufEmit(argsInitCode, OpI32Add);
  CodeBufEmit(argsInitCode, OpLocalSet); EmitULEB128(argsInitCode, 1);
  CodeBufEmit(argsInitCode, OpBr); EmitULEB128(argsInitCode, 0);

  CodeBufEmit(argsInitCode, OpEnd); { end loop }
  CodeBufEmit(argsInitCode, OpEnd); { end block }
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

{** Emit a call to the __write_int runtime helper.

  The integer value is already on the WASM operand stack at the
  point of the call. __write_int is a compiler-generated WASM
  function (see EnsureWriteInt / the int-to-str helper) that
  converts the i32 to an ASCII decimal representation in a
  scratch buffer and then calls fd_write(1, ...) to print it.
  Separating the helper from inline emission keeps call sites
  cheap — just a single call instruction.

  ;; WAT: call $__write_int
}
procedure EmitWriteInt;
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

function EnsureHeapAlloc: longint;
{** Ensure the heap helpers are registered and the free-list head exists.
  __heap_alloc(size) -> addr is at slot 24. }
begin
  if not needsHeap then begin
    needsHeap := true;
    addrHeapFree := AllocDataAligned(4, 4);
    DataBufEmit(secData, 0);
    DataBufEmit(secData, 0);
    DataBufEmit(secData, 0);
    DataBufEmit(secData, 0);
  end;
  EnsureHeapAlloc := numImports + 24;
end;

function EnsureHeapFree: longint;
{** __heap_free(addr) is at slot 25. Registers the free-list head too, since
  a program can in principle dispose of something it never allocated and the
  helper still needs somewhere to put it. }
begin
  EnsureHeapAlloc;
  EnsureHeapFree := numImports + 25;
end;

function EnsureNilCheck: longint;
{** Ensure the __nil_check helper is registered.
  __nil_check(addr) -> addr is at slot 23. Traps if addr is zero. }
begin
  needsNilCheck := true;
  EnsureNilCheck := numImports + 23;
end;

procedure EmitNilCheck;
{** Guard a dereference. The address is on the operand stack and is left
  there. Reading through nil would otherwise hit the four-byte nil guard and
  quietly return zeros, which is the failure this catches: the program keeps
  running on a value it never stored.

  Omitted when stack checks are off, where the guard bytes at address 0 are
  the only protection left. }
begin
  if optStackChecks then
    EmitCall(EnsureNilCheck);
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
  EmitLocalSet(localIdx);
  { iovec.buf = addr + 1 (skip length byte) }
  EmitI32Const(addrIovec);
  EmitLocalGet(localIdx);
  EmitI32Const(1);
  EmitOp(OpI32Add);
  EmitI32Store(2, 0);
  { iovec.len = addr[0] (length byte) }
  EmitI32Const(addrIovec + 4);
  EmitLocalGet(localIdx);
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

{** Parse an expression using precedence climbing (Pratt).

  minPrec is the minimum binding power this call will accept; an
  operator with lower precedence terminates the loop and returns to
  the caller. Called initially with minPrec = 0 (accept anything).

  Grammar precedence (highest to lowest):
    7  unary + - not
    6  * / div mod and shl shr
    5  + - or xor
    4  = <> < <= > >= in

  Prefix operators and primary expressions are dispatched before the
  loop; infix operators inside it. Emits WASM directly to startCode:
  operands are pushed, then the operator opcode, in the natural
  stack-machine order. Type checking and promotion happen inline.

  @param minPrec minimum operator precedence to accept
}
procedure ParseExpression(minPrec: longint);
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
  savedConcatPieces, savedConcatBase: longint;
  heapIsNew: boolean;
  heapTargetSize: longint;
  argTyp, argTypeIdx: longint;
  pieceSaveBytes: longint;
  retMark, saveMark: longint;
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
  retBufSize: longint;
  wantAddr: boolean;
  leftTypeIdx: longint;
  ptrTgtTyp, ptrTgtIdx, ptrTgtSize, ptrTgtStrMax: longint;
begin
  withFound := false;
  leftSetSize := 4;
  concatSPAllocs := 0;
  { Address-of. The designator that follows is parsed by the ordinary
    variable path below; wantAddr only tells that path to stop one step
    short, leaving the address it computed instead of loading through it. }
  wantAddr := false;
  if tokKind = tkAt then begin
    wantAddr := true;
    NextToken;
    if tokKind <> tkIdent then
      Expected('variable after ''@''');
  end;
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

    tkNil: begin
      { Address 0, which the nil guard reserves. Type index -1 marks the
        untyped nil, compatible with every pointer type. }
      EmitI32Const(0);
      exprType := tyPointer;
      exprTypeIdx := -1;
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
          EmitLocalSet(curStringTempIdx);
          EmitI32Const(addrConcatScratch + concatScratchBase + concatPieces * 4);
          EmitLocalGet(curStringTempIdx);
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
        EmitLocalTee(curStringTempIdx);
        EmitI32Const(0);
        EmitOp(OpI32LtS);
        EmitOp(OpIf);
        EmitOp(WasmI32);  { result type i32 }
        EmitI32Const(0);
        EmitLocalGet(curStringTempIdx);
        EmitOp(OpI32Sub);
        EmitOp(OpElse);
        EmitLocalGet(curStringTempIdx);
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
      else if tokStr = 'PARAMCOUNT' then begin
        { paramcount -> integer. Returns argc - 1 (excludes argv[0] program name). }
        NextToken;
        if tokKind = tkLParen then begin
          NextToken;
          Expect(tkRParen);
        end;
        EnsureArgsInit;
        EmitI32Const(addrArgc);
        EmitI32Load(2, 0);
        EmitI32Const(1);
        EmitOp(OpI32Sub);
        exprType := tyInteger;
      end
      else if tokStr = 'PARAMSTR' then begin
        { paramstr(n) -> string. Returns argv[n] as short string; n=0 is
          program name. Out-of-range indices mask to MaxArgs-1; slots
          argc..MaxArgs-1 are zero-filled so the return is an empty string. }
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('paramstr() requires integer argument');
        Expect(tkRParen);
        EnsureArgsInit;
        EmitI32Const(MaxArgs - 1);
        EmitOp(OpI32And);
        EmitI32Const(8);
        EmitOp(OpI32Shl);
        EmitI32Const(addrArgSlots);
        EmitOp(OpI32Add);
        exprType := tyString;
      end
      else if tokStr = 'SQR' then begin
        NextToken;
        Expect(tkLParen);
        ParseExpression(PrecNone);
        if exprType <> tyInteger then
          Error('sqr() requires integer argument');
        Expect(tkRParen);
        curFuncNeedsStringTemp := true;
        EmitLocalTee(curStringTempIdx);
        EmitLocalGet(curStringTempIdx);
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
      else if (tokStr = 'LO') and (LookupSym(tokStr) < 0) then begin
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
      else if (tokStr = 'HI') and (LookupSym(tokStr) < 0) then begin
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
              EmitLocalGet(-(withOffset[wi] + 1));
            end else if withIsLocal[wi] then begin
              EmitLocalGet(-(withOffset[wi] + 1));
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
          exprTypeIdx := syms[sym].typeIdx;
          exprStrMax := syms[sym].strMax;
          hasAddr := (exprType = tyArray) or (exprType = tyRecord)
                     or (exprType = tySet);
          NextToken;

          { Structured typed consts support .field / [index] selectors;
            offset holds the data-segment base address. }
          while hasAddr and ((tokKind = tkDot) or (tokKind = tkLBrack)) do begin
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

          { Load scalar value when selectors reduced a structured const to a scalar.
            Large sets (>4 bytes) keep the address since set ops work on memory. }
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
              EmitLocalGet(-(syms[sym].offset + 1));
              hasAddr := true;
            end else begin
              { Scalar value param: local holds the value }
              EmitLocalGet(-(syms[sym].offset + 1));
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

          { Process .field, [index], and ^ selectors — address must be on stack }
          while (tokKind = tkDot) or (tokKind = tkLBrack)
                or (tokKind = tkCaret) do begin
            if tokKind = tkCaret then begin
              { Dereference. When the address of the pointer is on the stack,
                load through it to get the pointer's value; when the pointer
                is a scalar value parameter its value is already there. Either
                way the result is an address, so selectors can continue. }
              if exprType <> tyPointer then
                Error('pointer type expected before ''^''');
              if exprTypeIdx < 0 then
                Error('cannot dereference nil');
              if hasAddr then
                EmitI32Load(2, 0);
              EmitNilCheck;
              exprType := types[exprTypeIdx].elemType;
              exprStrMax := types[exprTypeIdx].elemStrMax;
              exprTypeIdx := types[exprTypeIdx].elemTypeIdx;
              hasAddr := true;
              NextToken;
            end
            else if not hasAddr then
              Error('cannot apply selector to value parameter')
            else if tokKind = tkDot then begin
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

          if wantAddr then begin
            { @designator: keep the address the selectors computed and call it
              a pointer to whatever they arrived at. Structured types already
              leave an address, so the only thing to skip is the final load. }
            if not hasAddr then
              Error('cannot take the address of a value parameter');
            ptrTgtTyp := exprType;
            ptrTgtIdx := exprTypeIdx;
            ptrTgtStrMax := exprStrMax;
            if ptrTgtTyp = tyString then
              ptrTgtSize := exprStrMax + 1
            else if (ptrTgtTyp = tyRecord) or (ptrTgtTyp = tyArray)
                    or (ptrTgtTyp = tySet) then
              ptrTgtSize := types[ptrTgtIdx].size
            else
              ptrTgtSize := 4;
            exprType := tyPointer;
            exprTypeIdx := FindOrAddPointerType(ptrTgtTyp, ptrTgtIdx,
                                                ptrTgtSize, ptrTgtStrMax);
            exprStrMax := 0;
            wantAddr := false;
          end
          { Final load: scalars need i32.load, structured types leave address }
          else if hasAddr and (exprType <> tyString) and (exprType <> tyRecord)
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
          { Two stack areas are taken here, and the order is load-bearing
            because every address below is derived from $sp by adding back
            what was taken after it. Highest first:

              pending concat pieces   (pieceSaveBytes)
              structured result       (retBufSize)
              concat temps for args   (concatSPAllocs * 256, taken later)

            The concat temps are released right after the call; the other two
            live until the statement ends. }
          { Arguments get their own concat nesting level. Without this, an
            argument that finalizes a concatenation consumes the pending
            pieces of the expression the call sits inside, because the piece
            count and the scratch slots are both global. `a + F(b)` used to
            hand F the pieces belonging to the outer `+`.

            The compile-time rebase is not enough on its own. The callee's
            body was compiled at base zero, so at run time it writes over the
            caller's slots regardless of what the caller chose. Pending pieces
            are therefore copied onto the stack across the call. The copy is
            emitted only when there are pieces to protect, so an ordinary call
            outside a concatenation costs nothing. }
          savedConcatPieces := concatPieces;
          savedConcatBase := concatScratchBase;
          pieceSaveBytes := 0;
          if concatPieces > 0 then begin
            pieceSaveBytes := concatPieces * 4;
            EmitGlobalGet(0);
            EmitI32Const(pieceSaveBytes);
            EmitOp(OpI32Sub);
            EmitGlobalSet(0);
            for fi := 0 to concatPieces - 1 do begin
              EmitGlobalGet(0);
              if fi > 0 then begin
                EmitI32Const(fi * 4);
                EmitOp(OpI32Add);
              end;
              EmitI32Const(addrConcatScratch + concatScratchBase + fi * 4);
              EmitI32Load(2, 0);
              EmitI32Store(2, 0);
            end;
            stmtUsedResultBuf := true;  { released with the statement }
            stmtArenaBytes := stmtArenaBytes + pieceSaveBytes;
            saveMark := stmtArenaBytes;
          end;
          concatScratchBase := concatScratchBase + concatPieces * 4;
          concatPieces := 0;
          if concatScratchBase + 68 > ConcatScratchBytes then
            Error('string concatenation nested too deeply');
          { The result buffer, below the saved pieces. It lives until the end
            of the statement so the caller can use the value it holds. }
          retBufSize := 0;
          retMark := 0;
          if IsStructuredRet(funcs[syms[sym].size].retTyp) then begin
            retBufSize := (funcs[syms[sym].size].retSize + 3) and (not 3);
            EmitGlobalGet(0);
            EmitI32Const(retBufSize);
            EmitOp(OpI32Sub);
            EmitGlobalSet(0);
            stmtUsedResultBuf := true;
            stmtArenaBytes := stmtArenaBytes + retBufSize;
            retMark := stmtArenaBytes;
          end;
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
                    EmitLocalSet(curStringTempIdx);
                    { Allocate 256 bytes on WASM stack }
                    EmitGlobalGet(0);
                    EmitI32Const(256);
                    EmitOp(OpI32Sub);
                    EmitGlobalSet(0);
                    concatSPAllocs := concatSPAllocs + 1;
                    { Zero concat temp at $sp }
                    EmitGlobalGet(0);
                    EmitI32Const(0);
                    EmitOp(OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
                    { Append each saved piece }
                    for fi := 0 to concatPieces - 1 do begin
                      EmitGlobalGet(0);
                      EmitI32Const(255);
                      EmitI32Const(addrConcatScratch + concatScratchBase + fi * 4);
                      EmitI32Load(2, 0);
                      EmitCall(EnsureStrAppend);
                    end;
                    { Append last piece }
                    EmitGlobalGet(0);
                    EmitI32Const(255);
                    EmitLocalGet(curStringTempIdx);
                    EmitCall(EnsureStrAppend);
                    { Push SP (concat temp address) as the argument }
                    EmitGlobalGet(0);
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
                    EmitLocalGet(-(syms[argSym].offset + 1));
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
                  { Postfix selectors on a var argument. Only [index] was
                    handled, which was enough while a designator could not
                    reach through a pointer. `Insert(t^.left, v)` is the
                    ordinary way to write a tree, so ^ and .field are handled
                    too. Only the address is computed here; the argument is a
                    reference, so no load follows. }
                  argTyp := syms[argSym].typ;
                  argTypeIdx := syms[argSym].typeIdx;
                  while (tokKind = tkLBrack) or (tokKind = tkDot)
                        or (tokKind = tkCaret) do begin
                    if tokKind = tkCaret then begin
                      if argTyp <> tyPointer then
                        Error('pointer type expected before ''^''');
                      if argTypeIdx < 0 then
                        Error('cannot dereference nil');
                      EmitI32Load(2, 0);
                      EmitNilCheck;
                      argTyp := types[argTypeIdx].elemType;
                      argTypeIdx := types[argTypeIdx].elemTypeIdx;
                      NextToken;
                    end
                    else if tokKind = tkDot then begin
                      if argTyp <> tyRecord then
                        Error('record type expected before ''.''');
                      NextToken;
                      if tokKind <> tkIdent then
                        Expected('field name');
                      fldIdx := LookupField(argTypeIdx, tokStr);
                      if fldIdx < 0 then
                        Error('unknown field: ' + tokStr);
                      if fields[fldIdx].offset <> 0 then begin
                        EmitI32Const(fields[fldIdx].offset);
                        EmitOp(OpI32Add);
                      end;
                      argTyp := fields[fldIdx].typ;
                      argTypeIdx := fields[fldIdx].typeIdx;
                      NextToken;
                    end
                    else begin
                      if argTyp <> tyArray then
                        Error('array type expected before ''[''');
                      NextToken;
                      ParseExpression(PrecNone);
                      if types[argTypeIdx].arrLo <> 0 then begin
                        EmitI32Const(types[argTypeIdx].arrLo);
                        EmitOp(OpI32Sub);
                      end;
                      if types[argTypeIdx].elemSize <> 1 then begin
                        EmitI32Const(types[argTypeIdx].elemSize);
                        EmitOp(OpI32Mul);
                      end;
                      EmitOp(OpI32Add);
                      argTyp := types[argTypeIdx].elemType;
                      argTypeIdx := types[argTypeIdx].elemTypeIdx;
                      Expect(tkRBrack);
                    end;
                  end;
                  argSym := -1; { no longer tracking the original symbol }
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
          concatPieces := savedConcatPieces;
          concatScratchBase := savedConcatBase;
          { A structured result goes through a buffer this call site allocated
            before the arguments were evaluated. Its address is the current
            $sp plus whatever the arguments pushed below it, which is exactly
            the concat scratch that is about to be released. Deriving it that
            way avoids spending a local to hold it. }
          if retBufSize > 0 then begin
            EmitGlobalGet(0);
            if (stmtArenaBytes - retMark) + concatSPAllocs * 256 > 0 then begin
              EmitI32Const((stmtArenaBytes - retMark) + concatSPAllocs * 256);
              EmitOp(OpI32Add);
            end;
          end;
          EmitCall(syms[sym].offset);
          { Restore SP for any concat temp allocations }
          if concatSPAllocs > 0 then begin
            EmitGlobalGet(0);
            EmitI32Const(concatSPAllocs * 256);
            EmitOp(OpI32Add);
            EmitGlobalSet(0);
            concatSPAllocs := 0;
          end;
          { Copy the protected pieces back, now that the callee can no longer
            write over them. The save area sits just above the result buffer,
            the concat temps having been released. }
          if pieceSaveBytes > 0 then begin
            for fi := 0 to concatPieces - 1 do begin
              EmitI32Const(addrConcatScratch + concatScratchBase + fi * 4);
              EmitGlobalGet(0);
              if (stmtArenaBytes - saveMark) + fi * 4 > 0 then begin
                EmitI32Const((stmtArenaBytes - saveMark) + fi * 4);
                EmitOp(OpI32Add);
              end;
              EmitI32Load(2, 0);
              EmitI32Store(2, 0);
            end;
            pieceSaveBytes := 0;
          end;
          exprType := syms[sym].typ;
          if retBufSize > 0 then begin
            { The call returned nothing; the value of the expression is the
              buffer. It stays allocated until the statement ends, so its
              address is $sp plus whatever was taken below it since. }
            EmitGlobalGet(0);
            if stmtArenaBytes - retMark > 0 then begin
              EmitI32Const(stmtArenaBytes - retMark);
              EmitOp(OpI32Add);
            end;
            exprTypeIdx := funcs[syms[sym].size].retTypeIdx;
            exprStrMax := funcs[syms[sym].size].retStrMax;
            retBufSize := 0;
          end;
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
            EmitLocalSet(curStringTempIdx);
            ParseExpression(PrecNone);
            if tokKind = tkDotDot then begin
              curFuncNeedsCaseTemp := true;
              EmitLocalSet(curCaseTempIdx);
              EmitI32Const(-1);
              EmitLocalGet(curCaseTempIdx);
              EmitOp(OpI32Shl);
              NextToken;
              ParseExpression(PrecNone);
              EmitI32Const(1);
              EmitOp(OpI32Add);
              EmitLocalSet(curCaseTempIdx);
              EmitI32Const(-1);
              EmitLocalGet(curCaseTempIdx);
              EmitOp(OpI32Shl);
              EmitOp(OpI32Xor);
            end else begin
              curFuncNeedsCaseTemp := true;
              EmitLocalSet(curCaseTempIdx);
              EmitI32Const(1);
              EmitLocalGet(curCaseTempIdx);
              EmitOp(OpI32Shl);
            end;
            EmitLocalGet(curStringTempIdx);
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
      EmitLocalSet(curStringTempIdx);
      EmitI32Const(addrConcatScratch + concatScratchBase + concatPieces * 4);
      EmitLocalGet(curStringTempIdx);
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
      EmitLocalSet(curStringTempIdx);  { save char value }
      EmitI32Const(addrCharStr);
      EmitI32Const(1);
      EmitOp(OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);  { len=1 }
      EmitI32Const(addrCharStr + 1);
      EmitLocalGet(curStringTempIdx);
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
        EmitLocalSet(curCaseTempIdx);  { save right }
        { String addr on stack. Load byte at addr+1 (skip length byte) }
        EmitI32Const(1);
        EmitOp(OpI32Add);
        EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
        EmitLocalGet(curCaseTempIdx);  { restore right }
        leftType := tyChar;
      end;
      if exprSetSize > 4 then begin
        { Large set IN: stack has elem, set_addr.
          Compute: load byte at set_addr + (elem div 8), test bit (elem mod 8) }
        curFuncNeedsCaseTemp := true;
        curFuncNeedsStringTemp := true;
        EmitLocalSet(curCaseTempIdx);   { save set_addr }
        EmitLocalSet(curStringTempIdx);  { save elem }
        { An ordinal outside the set's storage must test false, not read
          past the set. elem is forced to 0 when out of range, so the load
          always lands inside the set, and the result is masked to 0 at the
          end. Unsigned compare rejects negatives in the same test. }
        { Compute set_addr + (clamped div 8). The clamped ordinal is
          recomputed rather than stored, so curStringTempIdx keeps the
          original value for the range mask at the end. }
        EmitLocalGet(curCaseTempIdx);
        EmitLocalGet(curStringTempIdx);
        EmitLocalGet(curStringTempIdx);
        EmitI32Const(exprSetSize * 8);
        EmitOp(OpI32LtU);
        EmitOp(OpI32Mul);   { elem, or 0 when out of range }
        EmitI32Const(3);
        EmitOp(OpI32ShrU);  { elem div 8 = elem >> 3 }
        EmitOp(OpI32Add);   { set_addr + byte_index }
        EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0); { load byte, align=0, offset=0 }
        { Shift right by (clamped mod 8) and test bit 0 }
        EmitLocalGet(curStringTempIdx);
        EmitLocalGet(curStringTempIdx);
        EmitI32Const(exprSetSize * 8);
        EmitOp(OpI32LtU);
        EmitOp(OpI32Mul);
        EmitI32Const(7);
        EmitOp(OpI32And);   { elem mod 8 }
        EmitOp(OpI32ShrU);  { byte >> bit_pos }
        EmitI32Const(1);
        EmitOp(OpI32And);   { isolate bit }
      end else begin
        { Small set IN: (1 << elem) AND set <> 0 }
        { Stack: elem, set. Save set to caseTemp, compute 1 << elem, AND. }
        curFuncNeedsCaseTemp := true;
        EmitLocalSet(curCaseTempIdx);  { save set }
        curFuncNeedsStringTemp := true;
        EmitLocalSet(curStringTempIdx);
        { WASM masks a shift count to five bits, so without a range test
          "99 in s" would alias to bit 3 and report true. Force the shift
          to 0 when the ordinal is out of range, then mask the result to
          false. Unsigned compare rejects negatives in the same test. }
        EmitI32Const(1);
        EmitLocalGet(curStringTempIdx);
        EmitLocalGet(curStringTempIdx);
        EmitI32Const(32);
        EmitOp(OpI32LtU);
        EmitOp(OpI32Mul);     { elem, or 0 when out of range }
        EmitOp(OpI32Shl);     { 1 << elem }
        EmitLocalGet(curCaseTempIdx);
        EmitOp(OpI32And);
        EmitI32Const(0);
        EmitOp(OpI32Ne);
      end;
      { Mask the membership result to false when the ordinal was out of
        range for the set's representation. }
      EmitLocalGet(curStringTempIdx);
      if exprSetSize > 4 then
        EmitI32Const(exprSetSize * 8)
      else
        EmitI32Const(32);
      EmitOp(OpI32LtU);
      EmitOp(OpI32And);
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
          EmitLocalSet(curCaseTempIdx);
          EmitOp(OpDrop);
          EmitI32Const(addrSetZero);
          EmitLocalGet(curCaseTempIdx);
        end;
        curFuncNeedsCaseTemp := true;
        curFuncNeedsStringTemp := true;
        EmitLocalSet(curCaseTempIdx);    { save b_addr }
        EmitLocalSet(curStringTempIdx);  { save a_addr }
        if op in [tkPlus, tkMinus, tkStar] then begin
          { Arithmetic: call helper(dst, a, b), push dst addr }
          EnsureSetTemp;
          if setTempFlip then fi := addrSetTemp2
          else fi := addrSetTemp;
          setTempFlip := not setTempFlip;
          EmitI32Const(fi);                        { dst }
          EmitLocalGet(curStringTempIdx); { a }
          EmitLocalGet(curCaseTempIdx);   { b }
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
              EmitLocalGet(curStringTempIdx);
              EmitLocalGet(curCaseTempIdx);
              EmitCall(EnsureSetEq);
              if op = tkNotEqual then
                EmitOp(OpI32Eqz);
            end;
            tkLessEq: begin              { subset: a <= b }
              EmitLocalGet(curStringTempIdx);
              EmitLocalGet(curCaseTempIdx);
              EmitCall(EnsureSetSubset);
            end;
            tkGreaterEq: begin           { superset: a >= b means b <= a }
              EmitLocalGet(curCaseTempIdx);   { b first }
              EmitLocalGet(curStringTempIdx);  { a second }
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
            EmitLocalSet(curCaseTempIdx);  { save B }
            EmitI32Const(-1);
            EmitOp(OpI32Xor);          { NOT A }
            EmitLocalGet(curCaseTempIdx);
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
    end
    else if (leftType = tyPointer) or (exprType = tyPointer) then begin
      { Pointers compare by address and nothing else. Ordering is left out
        deliberately: two pointers into different objects have no meaningful
        order, and the one case where it would be defined, comparing into the
        same array, is better written on the indices. }
      if (leftType <> tyPointer) or (exprType <> tyPointer) then
        Error('pointer compared with a non-pointer value');
      if op = tkEqual then
        EmitOp(OpI32Eq)
      else if op = tkNotEqual then
        EmitOp(OpI32Ne)
      else
        Error('only = and <> are defined for pointers');
      exprType := tyBoolean;
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
            EmitLocalSet(curStringTempIdx);
            if fd <> 1 then begin
              { Park the final piece in scratch memory. EmitInlineWriteStr
                below uses curStringTempIdx as its own scratch and would
                otherwise overwrite the address before we get to it. }
              EmitI32Const(addrConcatScratch + concatScratchBase + concatPieces * 4);
              EmitLocalGet(curStringTempIdx);
              EmitI32Store(2, 0);
            end;
            for i := 0 to concatPieces - 1 do begin
              EmitI32Const(addrConcatScratch + concatScratchBase + i * 4);
              EmitI32Load(2, 0);
              if fd = 1 then
                EmitCall(EnsureWriteStr)
              else
                EmitInlineWriteStr(fd, curStringTempIdx);
            end;
            if fd = 1 then begin
              EmitLocalGet(curStringTempIdx);
              EmitCall(EnsureWriteStr);
            end else begin
              EmitI32Const(addrConcatScratch + concatScratchBase + concatPieces * 4);
              EmitI32Load(2, 0);
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
        end else if exprType = tyPointer then begin
          { A raw address is not output. Printing one is almost always a
            debugging accident, and the number means nothing outside the
            run that produced it. }
          Error('cannot write a pointer; write what it points at')
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
          EmitLocalSet(curStringTempIdx);
          EmitVarParamPtr(sym);
          EmitLocalGet(curStringTempIdx);
          EmitI32Store8(0);
        end else if syms[sym].offset < 0 then begin
          { WASM local }
          EmitLocalSet(-(syms[sym].offset + 1));
        end else begin
          { Stack frame variable: store byte at frame offset }
          curFuncNeedsStringTemp := true;
          EmitLocalSet(curStringTempIdx);
          EmitFramePtr(syms[sym].level);
          EmitI32Const(syms[sym].offset);
          EmitOp(OpI32Add);
          EmitLocalGet(curStringTempIdx);
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
        EmitLocalSet(-(syms[sym].offset + 1));
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
        else if (tokStr = 'LO') and (LookupSym(tokStr) < 0) then begin
          NextToken; Expect(tkLParen);
          EvalConstExpr(outVal, outTyp);
          if outTyp <> tyInteger then
            Error('lo() requires integer argument');
          outVal := outVal and $FF;
          Expect(tkRParen);
        end
        else if (tokStr = 'HI') and (LookupSym(tokStr) < 0) then begin
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

procedure ResolvePendingPointers;
{** Fill in the targets of forward pointer references opened by the type
  declaration block that is now ending. A name that never appeared is an
  error: the alternative, leaving the target unknown, would let p^ compile
  with no idea what it dereferences.

  The descriptors are not merged with an equivalent resolved one here. Two
  descriptors for the same pointer type are harmless because compatibility
  compares targets, not descriptor indices. }
var i, typId, lineStr: longint;
  lineText: string[11];
begin
  for i := 0 to numPendingPtr - 1 do begin
    typId := LookupSym(pendingPtrName[i]);
    lineStr := pendingPtrLine[i];
    str(lineStr, lineText);
    if typId < 0 then
      Error('forward pointer type ^' + pendingPtrName[i] + ' on line ' +
            lineText + ' was never declared');
    if syms[typId].kind <> skType then
      Error(pendingPtrName[i] + ' is not a type');
    types[pendingPtrType[i]].elemType := syms[typId].typ;
    types[pendingPtrType[i]].elemTypeIdx := syms[typId].typeIdx;
    if syms[typId].typ = tyString then begin
      types[pendingPtrType[i]].elemStrMax := syms[typId].strMax;
      if types[pendingPtrType[i]].elemStrMax = 0 then
        types[pendingPtrType[i]].elemStrMax := 255;
      types[pendingPtrType[i]].elemSize :=
        types[pendingPtrType[i]].elemStrMax + 1;
    end else if (syms[typId].typ = tyRecord) or (syms[typId].typ = tyArray)
                or (syms[typId].typ = tySet) then
      types[pendingPtrType[i]].elemSize := types[syms[typId].typeIdx].size
    else
      types[pendingPtrType[i]].elemSize := 4;
  end;
  numPendingPtr := 0;
  optFileIO := false;
  emittedAnyCode := false;
  idxPathOpen := -1;
  idxFdClose := -1;
  stmtUsedResultBuf := false;
  stmtArenaBytes := 0;
end;

procedure CheckPointerAssign(dTyp: longint);
{** Reject mixing pointers and non-pointers across an assignment.

  Only the type tag is checked, not the target type, because the expression
  parser reports its result type in a global but keeps the descriptor index
  in a local. That catches p := 5 and i := p, the mistakes that produce a
  wild address; assigning between two pointer types with different targets
  is not yet caught. }
begin
  if (dTyp = tyPointer) and (exprType <> tyPointer) then
    Error('pointer value expected on the right of '':=''');
  if (dTyp <> tyPointer) and (exprType = tyPointer) then
    Error('cannot assign a pointer to a non-pointer variable');
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
  desBaseIsValue: boolean;
  fldIdx: longint;
  withFound: boolean;
  wi: longint;
  tmpOfs: longint;
  savedBreak: longint;
  savedContinue: longint;
  limitAddr: longint;
  concatSPAllocs: longint;
  fi: longint;
  savedUsedResultBuf: boolean;
  savedConcatPieces, savedConcatBase: longint;
  heapIsNew: boolean;
  heapTargetSize: longint;
  argTyp, argTypeIdx: longint;
begin
  concatSPAllocs := 0;
  { A structured function result is a buffer taken from the stack, and it has
    to outlive the call that filled it. Releasing it at the end of the
    statement is the shortest lifetime that works: a result can be an operand
    of anything within the statement, and nothing refers to it afterwards.

    The release is an absolute restore rather than a byte count, because
    display[curNestLevel] is the stack pointer's value at every statement
    boundary. That makes it correct no matter how many buffers the statement
    took, and it is why break and continue need nothing extra: they branch
    past their loop body's release, and the enclosing loop statement's own
    release runs at the branch target. }
  savedUsedResultBuf := stmtUsedResultBuf;
  { Deliberately not cleared. The flag carries two facts at once: that a
    release is owed, and that $sp is currently below the frame base. A nested
    statement that cleared it would go on to address frame variables through
    the $sp shortcut while an enclosing statement's buffer was still holding
    $sp down. The release is owed by whichever statement first displaced $sp,
    which is the one that sees `saved` false. }
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
      if (name = 'NEW') or (name = 'DISPOSE') then begin
        { new(p) / dispose(p) — p is a pointer variable, and the size comes
          from the pointer's target type rather than from an argument, so a
          caller cannot get it wrong. }
        heapIsNew := (name = 'NEW');
        NextToken;
        Expect(tkLParen);
        if tokKind <> tkIdent then
          Error('new/dispose requires a pointer variable');
        sym := LookupSym(tokStr);
        if sym < 0 then
          Error('undeclared identifier: ' + tokStr);
        if syms[sym].kind <> skVar then
          Error('new/dispose requires a pointer variable');
        if syms[sym].typ <> tyPointer then
          Error('new/dispose requires a pointer variable');
        if syms[sym].typeIdx < 0 then
          Error('cannot allocate through an untyped pointer');
        if syms[sym].isConstParam then
          Error('cannot assign to const parameter ''' + tokStr + '''');
        heapTargetSize := types[syms[sym].typeIdx].elemSize;
        if heapTargetSize <= 0 then
          Error('pointer target type has no size');
        NextToken;
        Expect(tkRParen);

        if syms[sym].offset < 0 then
          Error('cannot pass a value parameter to new/dispose');

        if heapIsNew then begin
          EmitPointerVarAddr(sym);
          EmitI32Const(heapTargetSize);
          EmitCall(EnsureHeapAlloc);
          EmitI32Store(2, 0);
        end else begin
          { Free the block, then clear the pointer. Clearing is not standard
            Pascal, which leaves the pointer dangling, but it turns a use
            after dispose into a nil trap under stack checks instead of a
            read of memory that now belongs to something else.

            The address is computed twice rather than duplicated: WASM 1.0
            has no dup, and spending a local here would collide with the
            string and case temps. }
          EmitPointerVarAddr(sym);
          EmitI32Load(2, 0);
          EmitNilCheck;
          EmitCall(EnsureHeapFree);
          EmitPointerVarAddr(sym);
          EmitI32Const(0);
          EmitI32Store(2, 0);
        end;
      end
      else if name = 'DELETE' then begin
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
          EmitLocalGet(-(syms[sym].offset + 1));
          if tokKind = tkComma then begin
            NextToken;
            ParseExpression(PrecNone);
          end else
            EmitI32Const(1);
          if name = 'INC' then
            EmitOp(OpI32Add)
          else
            EmitOp(OpI32Sub);
          EmitLocalSet(-(syms[sym].offset + 1));
        end else begin
          (* Stack frame variable: read-modify-write through memory *)
          EmitFramePtr(syms[sym].level);
          EmitI32Const(syms[sym].offset);
          EmitOp(OpI32Add);
          curFuncNeedsStringTemp := true;
          EmitLocalTee(curStringTempIdx);
          EmitLocalGet(curStringTempIdx);
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
          EmitLocalGet(-(syms[sym].offset + 1));
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
          EmitLocalGet(-(withOffset[wi] + 1));
        end else if withIsLocal[wi] then begin
          EmitLocalGet(-(withOffset[wi] + 1));
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
          CheckPointerAssign(desTyp);
          if (desTyp = tyChar) and (exprType = tyString) then begin
            EmitI32Const(1); EmitOp(OpI32Add);
            EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
          end;
          EmitStoreByType(desTyp);
        end;
      end
      else if (sym >= 0) and (syms[sym].kind = skVar) and
         ((tokKind = tkAssign) or (tokKind = tkDot) or (tokKind = tkLBrack)
          or (tokKind = tkCaret)) then begin
        { Assignment: var [:= | .field | [index] | ^ ...] := expr }
        if syms[sym].isConstParam then
          Error('cannot assign to const parameter ''' + name + '''');

        { Track designator type as we process selectors }
        desTyp := syms[sym].typ;
        desTypeIdx := syms[sym].typeIdx;
        desStrMax := syms[sym].strMax;
        desHasAddr := false;

        if (tokKind = tkDot) or (tokKind = tkLBrack) or (tokKind = tkCaret) then begin
          { Need to compute base address for selector chain }
          if syms[sym].isVarParam then begin
            EmitVarParamPtr(sym);
          end else if syms[sym].offset < 0 then begin
            EmitLocalGet(-(syms[sym].offset + 1));
          end else begin
            EmitFramePtr(syms[sym].level);
            EmitI32Const(syms[sym].offset);
            EmitOp(OpI32Add);
          end;
          desHasAddr := true;
          { A scalar value parameter's local holds the value, not an address.
            That only matters for a pointer, where the value already is the
            address its ^ needs, so the load below must be skipped once. }
          desBaseIsValue := (syms[sym].offset < 0) and (desTyp = tyPointer)
                            and not syms[sym].isVarParam;

          { Process .field, [index], and ^ selectors }
          while (tokKind = tkDot) or (tokKind = tkLBrack)
                or (tokKind = tkCaret) do begin
            if tokKind = tkCaret then begin
              if desTyp <> tyPointer then
                Error('pointer type expected before ''^''');
              if desTypeIdx < 0 then
                Error('cannot dereference nil');
              if not desBaseIsValue then
                EmitI32Load(2, 0);
              desBaseIsValue := false;
              EmitNilCheck;
              desTyp := types[desTypeIdx].elemType;
              desStrMax := types[desTypeIdx].elemStrMax;
              desTypeIdx := types[desTypeIdx].elemTypeIdx;
              NextToken;
            end
            else if tokKind = tkDot then begin
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
            EmitLocalSet(curStringTempIdx);
            { Build result in addrConcatTemp to avoid self-referencing bugs }
            { Zero temp[0] }
            EmitI32Const(addrConcatTemp);
            EmitI32Const(0);
            EmitOp(OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
            { Append saved pieces to temp }
            for i := 0 to concatPieces - 1 do begin
              EmitI32Const(addrConcatTemp);
              EmitI32Const(255);
              EmitI32Const(addrConcatScratch + concatScratchBase + i * 4);
              EmitI32Load(2, 0);
              EmitCall(EnsureStrAppend);
            end;
            { Append last piece (on stack via stringTemp) to temp }
            EmitI32Const(addrConcatTemp);
            EmitI32Const(255);
            EmitLocalGet(curStringTempIdx);
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
            EmitLocalSet(curStringTempIdx);
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
            EmitLocalGet(curStringTempIdx);
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
              EmitLocalGet(-(syms[sym].offset + 1));
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
          CheckPointerAssign(desTyp);
          if (desTyp = tyChar) and (exprType = tyString) then begin
            EmitI32Const(1); EmitOp(OpI32Add);
            EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
          end;
          EmitStoreByType(desTyp);
        end
        else if syms[sym].isVarParam then begin
          EmitVarParamPtr(sym);
          ParseExpression(PrecNone);
          CheckPointerAssign(desTyp);
          if (desTyp = tyChar) and (exprType = tyString) then begin
            EmitI32Const(1); EmitOp(OpI32Add);
            EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
          end;
          EmitStoreByType(desTyp);
        end
        else if syms[sym].offset < 0 then begin
          { WASM local (value parameter or function return value) }
          ParseExpression(PrecNone);
          CheckPointerAssign(desTyp);
          if (desTyp = tyChar) and (exprType = tyString) then begin
            EmitI32Const(1); EmitOp(OpI32Add);
            EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
          end;
          EmitLocalSet(-(syms[sym].offset + 1));
        end else begin
          { Stack frame variable (local or upvalue) }
          EmitFramePtr(syms[sym].level);
          EmitI32Const(syms[sym].offset);
          EmitOp(OpI32Add);
          ParseExpression(PrecNone);
          CheckPointerAssign(desTyp);
          if (desTyp = tyChar) and (exprType = tyString) then begin
            EmitI32Const(1); EmitOp(OpI32Add);
            EmitOp(OpI32Load8u); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
          end;
          EmitStoreByType(desTyp);
        end;
      end
      else if (sym >= 0) and (syms[sym].kind = skFunc)
              and ((tokKind = tkDot) or (tokKind = tkLBrack))
              and IsStructuredRet(funcs[syms[sym].size].retTyp) then
        { Assigning to a field or element of the result is ordinary Pascal and
          is not implemented: the result buffer is reachable only as a whole,
          through the hidden parameter. Say so, rather than falling through to
          the call path and failing on the selector with a complaint about a
          missing "end". }
        Error('cannot assign to a field or element of a function result; ' +
              'build the value in a local variable and assign that')
      else if (sym >= 0) and (syms[sym].kind = skFunc) and (tokKind = tkAssign) then begin
        { Function return value assignment: FuncName := expr }
        NextToken;
        fi := syms[sym].size;  { funcs[] index }

        if (funcs[fi].retTyp = tyString) then begin
          { The result lives in the caller's buffer, whose address arrived in
            the hidden trailing parameter at index nparams. Copy into it
            rather than overwriting the pointer. }
          ParseExpression(PrecNone);
          if exprType <> tyString then
            Error('string expression expected');
          if concatPieces > 0 then begin
            { Build the concatenation in the static temp first, for the same
              reason an ordinary string assignment does: the destination may
              be one of the operands. }
            curFuncNeedsStringTemp := true;
            EmitLocalSet(curStringTempIdx);
            EmitI32Const(addrConcatTemp);
            EmitI32Const(0);
            EmitOp(OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
            for i := 0 to concatPieces - 1 do begin
              EmitI32Const(addrConcatTemp);
              EmitI32Const(255);
              EmitI32Const(addrConcatScratch + concatScratchBase + i * 4);
              EmitI32Load(2, 0);
              EmitCall(EnsureStrAppend);
            end;
            EmitI32Const(addrConcatTemp);
            EmitI32Const(255);
            EmitLocalGet(curStringTempIdx);
            EmitCall(EnsureStrAppend);
            EmitLocalGet(funcs[fi].nparams);
            EmitI32Const(funcs[fi].retStrMax);
            EmitI32Const(addrConcatTemp);
            EmitCall(EnsureStrAssign);
            concatPieces := 0;
          end else begin
            curFuncNeedsStringTemp := true;
            EmitLocalSet(curStringTempIdx);
            EmitLocalGet(funcs[fi].nparams);
            EmitI32Const(funcs[fi].retStrMax);
            EmitLocalGet(curStringTempIdx);
            EmitCall(EnsureStrAssign);
          end;
        end
        else if (funcs[fi].retTyp = tyRecord) or (funcs[fi].retTyp = tyArray) then begin
          EmitLocalGet(funcs[fi].nparams);   { dst = caller's buffer }
          ParseExpression(PrecNone);          { src address }
          EmitI32Const(funcs[fi].retSize);
          EmitMemoryCopy;
        end
        else begin
          ParseExpression(PrecNone);
          { Store in the hidden WASM local at index nparams }
          EmitLocalSet(funcs[fi].nparams);
        end;
      end
      else if (sym >= 0) and ((syms[sym].kind = skProc) or (syms[sym].kind = skFunc)) then begin
        { Procedure/function call (discard result for functions) }
        savedConcatPieces := concatPieces;
        savedConcatBase := concatScratchBase;
        concatScratchBase := concatScratchBase + concatPieces * 4;
        concatPieces := 0;
        if concatScratchBase + 68 > ConcatScratchBytes then
          Error('string concatenation nested too deeply');
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
                  EmitLocalSet(curStringTempIdx);
                  { Allocate 256 bytes on WASM stack }
                  EmitGlobalGet(0);
                  EmitI32Const(256);
                  EmitOp(OpI32Sub);
                  EmitGlobalSet(0);
                  concatSPAllocs := concatSPAllocs + 1;
                  { Zero concat temp at $sp }
                  EmitGlobalGet(0);
                  EmitI32Const(0);
                  EmitOp(OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
                  { Append each saved piece }
                  for i := 0 to concatPieces - 1 do begin
                    EmitGlobalGet(0);
                    EmitI32Const(255);
                    EmitI32Const(addrConcatScratch + concatScratchBase + i * 4);
                    EmitI32Load(2, 0);
                    EmitCall(EnsureStrAppend);
                  end;
                  { Append last piece }
                  EmitGlobalGet(0);
                  EmitI32Const(255);
                  EmitLocalGet(curStringTempIdx);
                  EmitCall(EnsureStrAppend);
                  { Push SP (concat temp address) as the argument }
                  EmitGlobalGet(0);
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
                  EmitLocalGet(-(syms[argSym].offset + 1));
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
                  { Postfix selectors on a var argument. Only [index] was
                    handled, which was enough while a designator could not
                    reach through a pointer. `Insert(t^.left, v)` is the
                    ordinary way to write a tree, so ^ and .field are handled
                    too. Only the address is computed here; the argument is a
                    reference, so no load follows. }
                  argTyp := syms[argSym].typ;
                  argTypeIdx := syms[argSym].typeIdx;
                  while (tokKind = tkLBrack) or (tokKind = tkDot)
                        or (tokKind = tkCaret) do begin
                    if tokKind = tkCaret then begin
                      if argTyp <> tyPointer then
                        Error('pointer type expected before ''^''');
                      if argTypeIdx < 0 then
                        Error('cannot dereference nil');
                      EmitI32Load(2, 0);
                      EmitNilCheck;
                      argTyp := types[argTypeIdx].elemType;
                      argTypeIdx := types[argTypeIdx].elemTypeIdx;
                      NextToken;
                    end
                    else if tokKind = tkDot then begin
                      if argTyp <> tyRecord then
                        Error('record type expected before ''.''');
                      NextToken;
                      if tokKind <> tkIdent then
                        Expected('field name');
                      fldIdx := LookupField(argTypeIdx, tokStr);
                      if fldIdx < 0 then
                        Error('unknown field: ' + tokStr);
                      if fields[fldIdx].offset <> 0 then begin
                        EmitI32Const(fields[fldIdx].offset);
                        EmitOp(OpI32Add);
                      end;
                      argTyp := fields[fldIdx].typ;
                      argTypeIdx := fields[fldIdx].typeIdx;
                      NextToken;
                    end
                    else begin
                      if argTyp <> tyArray then
                        Error('array type expected before ''[''');
                      NextToken;
                      ParseExpression(PrecNone);
                      if types[argTypeIdx].arrLo <> 0 then begin
                        EmitI32Const(types[argTypeIdx].arrLo);
                        EmitOp(OpI32Sub);
                      end;
                      if types[argTypeIdx].elemSize <> 1 then begin
                        EmitI32Const(types[argTypeIdx].elemSize);
                        EmitOp(OpI32Mul);
                      end;
                      EmitOp(OpI32Add);
                      argTyp := types[argTypeIdx].elemType;
                      argTypeIdx := types[argTypeIdx].elemTypeIdx;
                      Expect(tkRBrack);
                    end;
                  end;
                  argSym := -1; { no longer tracking the original symbol }
              end;
            end else begin
              ParseExpression(PrecNone);
              if concatPieces > 0 then begin
                { String concat in regular param: finalize into string temp }
                curFuncNeedsStringTemp := true;
                curFuncNeedsCaseTemp := true;
                EmitLocalSet(curCaseTempIdx);
                EmitLocalGet(curStringTempIdx);
                EmitI32Const(0);
                EmitOp(OpI32Store8); EmitULEB128(startCode, 0); EmitULEB128(startCode, 0);
                for i := 0 to concatPieces - 1 do begin
                  EmitLocalGet(curStringTempIdx);
                  EmitI32Const(255);
                  EmitI32Const(addrConcatScratch + concatScratchBase + i * 4);
                  EmitI32Load(2, 0);
                  EmitCall(EnsureStrAppend);
                end;
                EmitLocalGet(curStringTempIdx);
                EmitI32Const(255);
                EmitLocalGet(curCaseTempIdx);
                EmitCall(EnsureStrAppend);
                EmitLocalGet(curStringTempIdx);
                concatPieces := 0;
              end;
            end;
            argIdx := argIdx + 1;
            if tokKind = tkComma then
              NextToken;
          end;
          Expect(tkRParen);
        end;
        concatPieces := savedConcatPieces;
        concatScratchBase := savedConcatBase;
        EmitCall(syms[sym].offset);
        { Restore SP for any concat temp allocations }
        if concatSPAllocs > 0 then begin
          EmitGlobalGet(0);
          EmitI32Const(concatSPAllocs * 256);
          EmitOp(OpI32Add);
          EmitGlobalSet(0);
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
      { Each iteration releases what its condition and body took, so a loop
        cannot walk the stack down one buffer at a time. }
      EmitStmtArenaRelease;
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

        { Body — wrapped in a block so continue (br 0) skips to increment }
        EmitOp(OpBlock);
        EmitOp(WasmVoid);
        savedBreak := breakDepth; savedContinue := continueDepth;
        breakDepth := 2; continueDepth := 0;
        if exitDepth >= 0 then exitDepth := exitDepth + 3;
        forLimitDepth := forLimitDepth + 1;
        ParseStatement;
        forLimitDepth := forLimitDepth - 1;
        if exitDepth >= 0 then exitDepth := exitDepth - 3;
        breakDepth := savedBreak; continueDepth := savedContinue;
        EmitOp(OpEnd); { end body block }
        EmitStmtArenaRelease;

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

        { Body — wrapped in a block so continue (br 0) skips to decrement }
        EmitOp(OpBlock);
        EmitOp(WasmVoid);
        savedBreak := breakDepth; savedContinue := continueDepth;
        breakDepth := 2; continueDepth := 0;
        if exitDepth >= 0 then exitDepth := exitDepth + 3;
        forLimitDepth := forLimitDepth + 1;
        ParseStatement;
        forLimitDepth := forLimitDepth - 1;
        if exitDepth >= 0 then exitDepth := exitDepth - 3;
        breakDepth := savedBreak; continueDepth := savedContinue;
        EmitOp(OpEnd); { end body block }
        { Release before touching the counter: the counter is a frame variable
          and the body may have left $sp displaced. }
        EmitStmtArenaRelease;

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
      EmitStmtArenaRelease;
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
      EmitLocalSet(curCaseTempIdx);
      Expect(tkOf);
      i := 0; { count of nested if blocks to close }
      while (tokKind <> tkEnd) and (tokKind <> tkElse) and (tokKind <> tkEOF) do begin
        (* Parse case labels: constexpr [.. constexpr] , ... *)
        desTyp := 0; { label count for OR-ing }
        repeat
          EmitLocalGet(curCaseTempIdx);
          EvalConstExpr(sym, argIdx);  { reusing sym and argIdx as temp vars }
          if tokKind = tkDotDot then begin
            { Range: selector >= lo AND selector <= hi }
            EmitI32Const(sym);
            EmitOp(OpI32GeS);
            EmitLocalGet(curCaseTempIdx);
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
      EmitStmtArenaRelease;
      EmitOp(OpBr);
      EmitULEB128(startCode, exitDepth);
    end;

    tkBreak: begin
      NextToken;
      if breakDepth < 0 then
        Error('break outside of loop');
      EmitStmtArenaRelease;
      EmitOp(OpBr);
      EmitULEB128(startCode, breakDepth);
    end;

    tkContinue: begin
      NextToken;
      if continueDepth < 0 then
        Error('continue outside of loop');
      EmitStmtArenaRelease;
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
  if stmtUsedResultBuf and not savedUsedResultBuf then begin
    EmitStmtArenaRelease;
    stmtUsedResultBuf := false;
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
  retTypeIdx, retSize, retStrMax: longint;
  retIsStructured: boolean;
  mismatchA, mismatchB: string[11];  { forward-header mismatch messages }
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
  nWasmParams: longint;
  savedNestLevel: longint;
  savedDisplayLocal: longint;
  myDisplayLocal: longint;
  savedStringTempIdx: longint;
  savedFuncNeedsStringTemp: boolean;
  savedCaseTempIdx: longint;
  savedFuncNeedsCaseTemp: boolean;
  savedFuncIsFunction: boolean;
  savedFuncReturnIdx: longint;
  savedFuncRetStructured: boolean;
  savedFuncRetTyp, savedFuncRetSize, savedFuncRetStrMax: longint;
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
  dbgParams, dbgLocals, dbgBytes: string[11];
  savedVarInitIsStr: array[0..15] of boolean;
  savedVarInitStrMax: array[0..15] of longint;
  localImportMod: string[63];
  localImportName: string[63];
  localExportPending: boolean;
  localExportName: string[63];
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

  { Parse return type for functions.

    ParseTypeSpec rather than a bare identifier, so `: string` and
    `: string[40]` are accepted alongside a named type. It also rejects an
    anonymous `record ... end` return by the grammar, which is deliberate:
    a caller has no way to name that type. }
  retTyp := tyNone;
  retTypeIdx := -1;
  retSize := 0;
  retStrMax := 0;
  if isFunc then begin
    Expect(tkColon);
    if (tokKind <> tkIdent) and (tokKind <> tkString_kw) then
      Expected('return type');
    if tokKind = tkString_kw then
      ParseTypeSpec(retTyp, retTypeIdx, retSize, retStrMax)
    else begin
      retTypSym := LookupSym(tokStr);
      if retTypSym < 0 then
        Error('unknown type: ' + tokStr);
      if syms[retTypSym].kind <> skType then
        Error(tokStr + ' is not a type');
      ParseTypeSpec(retTyp, retTypeIdx, retSize, retStrMax);
    end;
  end;
  { A structured result is returned through a caller-allocated buffer rather
    than on the WASM operand stack, which has no way to carry one. }
  retIsStructured := (retTyp = tyString) or (retTyp = tyRecord)
                     or (retTyp = tyArray);

  Expect(tkSemicolon);

  { Check for external declaration (WASM import) }
  if tokKind = tkExternal then begin
    if not hasPendingImport then
      Error('external requires preceding {$IMPORT} directive');
    localImportMod := pendingImportMod;
    localImportName := pendingImportName;
    hasPendingImport := false;
    NextToken;
    Expect(tkSemicolon);

    { A host function cannot be handed a caller-allocated buffer: the hidden
      parameter is a private arrangement between this compiler's own call
      sites and its own prologues, and nothing tells a host what to do with
      it. Rejecting is better than silently passing an address the host will
      read as an integer. }
    if retIsStructured then
      Error('an external function cannot return a structured type');

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
    funcIdx := AddImport(localImportMod, localImportName, typIdx);

    { Register in funcs table so call sites can look up param metadata }
    if numFuncs >= MaxFuncs then
      Error('too many functions');
    funcs[numFuncs].name := procName;
    funcs[numFuncs].typeidx := typIdx;
    funcs[numFuncs].bodyStart := -2; { marker: external import }
    funcs[numFuncs].bodyLen := 0;
    funcs[numFuncs].nlocals := 0;
    funcs[numFuncs].nparams := np;
    funcs[numFuncs].retTyp := retTyp;
    funcs[numFuncs].retTypeIdx := retTypeIdx;
    funcs[numFuncs].retSize := retSize;
    funcs[numFuncs].retStrMax := retStrMax;
    for i := 0 to np - 1 do
    begin
      funcs[numFuncs].varParams[i] := false; { imports have no var params }
      funcs[numFuncs].constParams[i] := false;
      funcs[numFuncs].paramTyp[i] := paramTypes[i];
      funcs[numFuncs].paramTypeIdx[i] := paramTypeIdx[i];
    end;

    { Add symbol - offset is the import index (absolute function index) }
    if isFunc then
      sym := AddSym(procName, skFunc, retTyp)
    else
      sym := AddSym(procName, skProc, tyNone);
    syms[sym].offset := funcIdx; { import index = absolute function index }
    syms[sym].size := numFuncs; { funcs[] index for param metadata }

    numFuncs := numFuncs + 1;
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

    { Build WASM type signature.

      A structured result adds a hidden trailing parameter holding the address
      of a caller-allocated buffer, and returns nothing. Trailing rather than
      leading so the visible parameters keep their indices, which leaves every
      existing argument-passing path untouched. }
    for i := 0 to np - 1 do
      wasmParams[i] := WasmI32;
    nWasmResults := 0;
    nWasmParams := np;
    if retIsStructured then begin
      wasmParams[np] := WasmI32;
      nWasmParams := np + 1;
    end else if isFunc then begin
      wasmResults[0] := WasmI32;
      nWasmResults := 1;
    end;
    typIdx := AddWasmType(nWasmParams, wasmParams, nWasmResults, wasmResults);

    { Register in funcs table with empty body }
    if numFuncs >= MaxFuncs then
      Error('too many functions');
    funcs[numFuncs].name := procName;
    funcs[numFuncs].typeidx := typIdx;
    funcs[numFuncs].bodyStart := -1; { marker: forward-declared, no body yet }
    funcs[numFuncs].bodyLen := 0;
    funcs[numFuncs].nlocals := 0;
    funcs[numFuncs].nparams := np;
    funcs[numFuncs].retTyp := retTyp;
    funcs[numFuncs].retTypeIdx := retTypeIdx;
    funcs[numFuncs].retSize := retSize;
    funcs[numFuncs].retStrMax := retStrMax;
    for i := 0 to np - 1 do begin
      funcs[numFuncs].varParams[i] := paramIsVar[i];
      funcs[numFuncs].constParams[i] := paramIsConst[i];
      funcs[numFuncs].paramTyp[i] := paramTypes[i];
      funcs[numFuncs].paramTypeIdx[i] := paramTypeIdx[i];
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

    { The header must repeat the forward declaration exactly. Without this
      check a differing parameter count emits a module that fails WASM
      validation, and a differing return type is accepted silently, leaving
      the caller to read the result as whatever the forward declared. }
    if funcs[funcIdx].bodyStart = -2 then
      Error('external ' + procName + ' cannot have a body');
    if isFunc <> (syms[sym].kind = skFunc) then begin
      if isFunc then
        Error(procName + ' was declared as a procedure, defined as a function')
      else
        Error(procName + ' was declared as a function, defined as a procedure');
    end;
    if np <> funcs[funcIdx].nparams then begin
      str(funcs[funcIdx].nparams, mismatchA);
      str(np, mismatchB);
      Error('header of ' + procName + ' does not match its forward declaration: '
            + mismatchA + ' parameters declared, ' + mismatchB + ' defined');
    end;
    for i := 0 to np - 1 do begin
      str(i + 1, mismatchA);
      if paramTypes[i] <> funcs[funcIdx].paramTyp[i] then
        Error('parameter ' + mismatchA + ' of ' + procName +
              ' has a different type than its forward declaration');
      if paramTypeIdx[i] <> funcs[funcIdx].paramTypeIdx[i] then
        Error('parameter ' + mismatchA + ' of ' + procName +
              ' has a different type than its forward declaration');
      if paramIsVar[i] <> funcs[funcIdx].varParams[i] then
        Error('parameter ' + mismatchA + ' of ' + procName +
              ' differs in var/const from its forward declaration');
      if paramIsConst[i] <> funcs[funcIdx].constParams[i] then
        Error('parameter ' + mismatchA + ' of ' + procName +
              ' differs in var/const from its forward declaration');
    end;
    if isFunc and (retTyp <> syms[sym].typ) then
      Error('return type of ' + procName +
            ' does not match its forward declaration');
  end else begin
    { New declaration - allocate slot }
    slot := numDefinedFuncs;
    numDefinedFuncs := numDefinedFuncs + 1;

    { Build WASM type signature.

      A structured result adds a hidden trailing parameter holding the address
      of a caller-allocated buffer, and returns nothing. Trailing rather than
      leading so the visible parameters keep their indices, which leaves every
      existing argument-passing path untouched. }
    for i := 0 to np - 1 do
      wasmParams[i] := WasmI32;
    nWasmResults := 0;
    nWasmParams := np;
    if retIsStructured then begin
      wasmParams[np] := WasmI32;
      nWasmParams := np + 1;
    end else if isFunc then begin
      wasmResults[0] := WasmI32;
      nWasmResults := 1;
    end;
    typIdx := AddWasmType(nWasmParams, wasmParams, nWasmResults, wasmResults);

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
    funcs[numFuncs].retTyp := retTyp;
    funcs[numFuncs].retTypeIdx := retTypeIdx;
    funcs[numFuncs].retSize := retSize;
    funcs[numFuncs].retStrMax := retStrMax;
    for i := 0 to np - 1 do begin
      funcs[numFuncs].varParams[i] := paramIsVar[i];
      funcs[numFuncs].constParams[i] := paramIsConst[i];
      funcs[numFuncs].paramTyp[i] := paramTypes[i];
      funcs[numFuncs].paramTypeIdx[i] := paramTypeIdx[i];
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
  { Index np is the scalar result local for a plain function and the hidden
    result-pointer parameter for a structured one. The two cases land on the
    same index on purpose: everything downstream that indexes locals, the
    display slot, the string temp, the case temp, stays as it was. Only the
    count of declared locals differs, since a parameter is not declared. }
  curFuncReturnIdx := np;
  savedFuncRetStructured := curFuncRetStructured;
  savedFuncRetTyp := curFuncRetTyp;
  savedFuncRetSize := curFuncRetSize;
  savedFuncRetStrMax := curFuncRetStrMax;
  curFuncRetStructured := retIsStructured;
  curFuncRetTyp := retTyp;
  curFuncRetSize := retSize;
  curFuncRetStrMax := retStrMax;

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
  EmitGlobalGet(curNestLevel + 1);  { display[N] = global N+1 }
  EmitLocalSet(displayLocalIdx);

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

  { For functions, push return value onto WASM stack. A structured result was
    written into the caller's buffer instead, so there is nothing to push and
    the WASM signature has no result. }
  if isFunc and not retIsStructured then begin
    EmitLocalGet(np); { local index for return value }
  end;

  localExportPending := hasPendingExport;
  localExportName := pendingExportName;
  if hasPendingExport then
    hasPendingExport := false;

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
  if isFunc and not retIsStructured then
    nlocals := 2; { return value + saved display }
  { A structured result lives in the hidden trailing parameter, not in a
    declared local, so index np is already accounted for by nparams. }
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
  curFuncRetStructured := savedFuncRetStructured;
  curFuncRetTyp := savedFuncRetTyp;
  curFuncRetSize := savedFuncRetSize;
  curFuncRetStrMax := savedFuncRetStrMax;

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
  if optDebug then begin
    str(nparams, dbgParams);
    str(nlocals, dbgLocals);
    str(startCode.len, dbgBytes);
    DebugAt('body of ' + funcs[funcIdx].name + ': ' + dbgParams +
            ' params, ' + dbgLocals + ' locals, ' + dbgBytes + ' bytes');
  end;
  for i := 0 to np - 1 do begin
    funcs[funcIdx].varParams[i] := paramIsVar[i];
    funcs[funcIdx].constParams[i] := paramIsConst[i];
  end;

  (* Record user export if EXPORT was pending *)
  if localExportPending then begin
    if numUserExports >= 32 then
      Error('too many exports');
    userExports[numUserExports].name := localExportName;
    userExports[numUserExports].funcIdx := syms[procSym].offset;
    numUserExports := numUserExports + 1;
  end;

  { Restore code emission state }
  savedCodeStackTop := savedCodeStackTop - 1;
  startCode := savedCodeStack[savedCodeStackTop];
  curFrameSize := savedFrameSize;
end;

{** Parse a Pascal declaration block followed by a begin/end compound body.

  Handles the full Pascal block structure: optional const/type/var
  sections (repeatable, in any order), nested procedure/function
  declarations, then the main begin..end compound statement. Called
  recursively for nested procedures via ParseProcDecl. Maintains
  curFrameSize across nested calls so each scope gets its own frame
  size bookkeeping. }
procedure EmitArrayInitializer(typeIdx: longint); forward;
procedure EmitRecordInitializer(typeIdx: longint); forward;
procedure EmitSetInitializer(typeIdx: longint); forward;

procedure EmitTypedConstField(fTyp, fTypeIdx, fSize, fStrMax: longint);
{** Emit bytes for one scalar or structured typed-constant component. }
var
  val, valTyp: longint;
  si: longint;
begin
  if fTyp = tyArray then
    EmitArrayInitializer(fTypeIdx)
  else if fTyp = tyRecord then
    EmitRecordInitializer(fTypeIdx)
  else if fTyp = tySet then
    EmitSetInitializer(fTypeIdx)
  else if fTyp = tyString then begin
    if tokKind <> tkString then
      Error('string constant expected');
    if length(tokStr) > fStrMax then
      Error('string literal exceeds type capacity');
    DataBufEmit(secData, byte(length(tokStr)));
    for si := 1 to length(tokStr) do
      DataBufEmit(secData, byte(ord(tokStr[si])));
    for si := length(tokStr) + 1 to fStrMax do
      DataBufEmit(secData, 0);
    NextToken;
  end else begin
    EvalConstExpr(val, valTyp);
    if fSize = 1 then
      DataBufEmit(secData, byte(val and $FF))
    else
      EmitDataI32Bytes(val);
  end;
end;

procedure EmitArrayInitializer(typeIdx: longint);
{** Emit bytes for a single array value to the current data segment position.
  Caller must have already reserved the array's size via AllocData/AllocDataAligned.
  Supports nested arrays, records/sets/strings as elements, and the
  `array[..] of char = 'literal'` shortcut. }
var
  n, i: longint;
  elemTyp, elemTypeIdx, elemSize, elemStrMax: longint;
  s: string;
begin
  elemTyp := types[typeIdx].elemType;
  elemTypeIdx := types[typeIdx].elemTypeIdx;
  elemSize := types[typeIdx].elemSize;
  elemStrMax := types[typeIdx].elemStrMax;
  n := types[typeIdx].arrHi - types[typeIdx].arrLo + 1;

  { array[lo..hi] of char = 'literal' — must match array length exactly }
  if (elemTyp = tyChar) and (tokKind = tkString) then begin
    s := tokStr;
    if length(s) <> n then
      Error('string literal length does not match array size');
    for i := 1 to n do
      EmitDataI32Bytes(ord(s[i]));
    NextToken;
    exit;
  end;

  Expect(tkLParen);
  for i := 1 to n do begin
    EmitTypedConstField(elemTyp, elemTypeIdx, elemSize, elemStrMax);
    if i < n then begin
      if tokKind <> tkComma then
        Error('too few elements in array initializer');
      NextToken;
    end;
  end;
  if tokKind = tkComma then
    Error('too many elements in array initializer');
  Expect(tkRParen);
end;

procedure EmitRecordInitializer(typeIdx: longint);
{** Emit bytes for a record typed constant.
  Syntax: (field: value; field: value; ...). For non-variant records,
  all fields must appear in declaration order. For variant records,
  fixed fields come first, then the tag field (required to determine
  which variant to initialize), then only the variant fields of the
  selected variant. Zero-fills remaining space. }
var
  fStart, fCount, fi, fldIdx: longint;
  expectedOff, curOff: longint;
  fldName: string;
  variantOfs: longint;
  tagValue: longint;
  tagTyp: longint;
  selectedVariantId: longint;
  hasVariants: boolean;
  tagFound: boolean;
begin
  Expect(tkLParen);
  fStart := types[typeIdx].fieldStart;
  fCount := types[typeIdx].fieldCount;
  curOff := 0;

  variantOfs := types[typeIdx].variantOfs;
  hasVariants := (variantOfs >= 0);
  tagFound := false;
  selectedVariantId := 0;

  { If the record has variants, we must see the tag field to know which variant }
  if hasVariants then begin
    { First pass: emit fixed fields and find the tag field }
    fi := 0;
    while fi < fCount do begin
      { If this is the tag field }
      if (fields[fStart + fi].variantId = 0) and (fields[fStart + fi].offset >= variantOfs) then begin
        { This is the tag field }
        if fields[fStart + fi].name = '' then
          Error('variant records with unnamed tags cannot be initialized with typed constants');

        expectedOff := fields[fStart + fi].offset;
        while curOff < expectedOff do begin
          DataBufEmit(secData, 0);
          curOff := curOff + 1;
        end;

        if tokKind <> tkIdent then
          Error('field name expected in record initializer');
        fldName := tokStr;
        if fldName <> fields[fStart + fi].name then
          Error('expected field ' + fields[fStart + fi].name
                + ' but got ' + fldName);
        NextToken;
        Expect(tkColon);

        { Evaluate the tag value }
        EvalConstExpr(tagValue, tagTyp);
        selectedVariantId := tagValue;

        { Emit the tag field value directly (already evaluated) }
        if fields[fStart + fi].size = 1 then
          DataBufEmit(secData, byte(tagValue and $FF))
        else
          EmitDataI32Bytes(tagValue);
        curOff := curOff + fields[fStart + fi].size;

        if fi < fCount - 1 then begin
          if tokKind <> tkSemicolon then
            Error('; expected between record fields');
          NextToken;
        end else if tokKind = tkSemicolon then
          NextToken;

        tagFound := true;
        fi := fi + 1;
        break;
      end else if fields[fStart + fi].variantId = 0 then begin
        { Regular fixed field }
        expectedOff := fields[fStart + fi].offset;
        while curOff < expectedOff do begin
          DataBufEmit(secData, 0);
          curOff := curOff + 1;
        end;

        if tokKind <> tkIdent then
          Error('field name expected in record initializer');
        fldName := tokStr;
        if fldName <> fields[fStart + fi].name then
          Error('expected field ' + fields[fStart + fi].name
                + ' but got ' + fldName);
        NextToken;
        Expect(tkColon);

        EmitTypedConstField(fields[fStart + fi].typ,
                            fields[fStart + fi].typeIdx,
                            fields[fStart + fi].size,
                            fields[fStart + fi].strMax);
        curOff := curOff + fields[fStart + fi].size;

        if fi < fCount - 1 then begin
          if tokKind <> tkSemicolon then
            Error('; expected between record fields');
          NextToken;
        end else if tokKind = tkSemicolon then
          NextToken;

        fi := fi + 1;
      end else
        fi := fi + 1;
    end;

    { Now process variant fields }
    if tagFound then begin
      while tokKind <> tkRParen do begin
        if tokKind <> tkIdent then
          Error('field name expected in record initializer');
        fldName := tokStr;

        { Find this field in the record }
        fldIdx := -1;
        for fi := 0 to fCount - 1 do begin
          if fields[fStart + fi].name = fldName then begin
            fldIdx := fi;
            break;
          end;
        end;

        if fldIdx < 0 then
          Error('unknown field: ' + fldName);

        { Check if this field is in the selected variant }
        if fields[fStart + fldIdx].variantId <> selectedVariantId then
          Error('field ' + fldName + ' not in variant');

        NextToken;
        Expect(tkColon);

        expectedOff := fields[fStart + fldIdx].offset;
        while curOff < expectedOff do begin
          DataBufEmit(secData, 0);
          curOff := curOff + 1;
        end;

        EmitTypedConstField(fields[fStart + fldIdx].typ,
                            fields[fStart + fldIdx].typeIdx,
                            fields[fStart + fldIdx].size,
                            fields[fStart + fldIdx].strMax);
        curOff := curOff + fields[fStart + fldIdx].size;

        if tokKind = tkSemicolon then
          NextToken
        else if tokKind <> tkRParen then
          Error('; or ) expected after field value');
      end;
    end;
  end else begin
    { Non-variant record: simple sequential processing }
    for fi := 0 to fCount - 1 do begin
      expectedOff := fields[fStart + fi].offset;
      while curOff < expectedOff do begin
        DataBufEmit(secData, 0);
        curOff := curOff + 1;
      end;

      if tokKind <> tkIdent then
        Error('field name expected in record initializer');
      fldName := tokStr;
      if fldName <> fields[fStart + fi].name then
        Error('expected field ' + fields[fStart + fi].name
              + ' but got ' + fldName);
      NextToken;
      Expect(tkColon);

      EmitTypedConstField(fields[fStart + fi].typ,
                          fields[fStart + fi].typeIdx,
                          fields[fStart + fi].size,
                          fields[fStart + fi].strMax);
      curOff := curOff + fields[fStart + fi].size;

      if fi < fCount - 1 then begin
        if tokKind <> tkSemicolon then
          Error('; expected between record fields');
        NextToken;
      end else if tokKind = tkSemicolon then
        NextToken;
    end;
  end;

  { Zero-fill remaining space to record size }
  while curOff < types[typeIdx].size do begin
    DataBufEmit(secData, 0);
    curOff := curOff + 1;
  end;

  Expect(tkRParen);
end;

procedure EmitSetInitializer(typeIdx: longint);
{** Emit bytes for a set typed constant.
  Syntax: [elem, elem, lo..hi, ...]. Elements must be compile-time
  constants (integer/char/enum literals or declared constants). Small
  sets (size=4) emit a 4-byte i32 bitmap; large sets emit
  types[typeIdx].size bytes of bitmap. }
var
  bm: array[0..31] of byte;
  i: longint;
  lo, hi: longint;
  sym: longint;
  setSize, setHiBound: longint;
begin
  for i := 0 to 31 do bm[i] := 0;
  setSize := types[typeIdx].size;
  setHiBound := types[typeIdx].arrHi;

  Expect(tkLBrack);
  if tokKind <> tkRBrack then begin
    repeat
      if tokKind = tkInteger then begin
        lo := tokInt; NextToken;
      end else if (tokKind = tkString) and (length(tokStr) = 1) then begin
        lo := ord(tokStr[1]); NextToken;
      end else if tokKind = tkIdent then begin
        sym := LookupSym(tokStr);
        if (sym < 0) or (syms[sym].kind <> skConst) then
          Error('constant expected in set initializer');
        lo := syms[sym].offset;
        NextToken;
      end else
        Error('constant expected in set initializer');

      if tokKind = tkDotDot then begin
        NextToken;
        if tokKind = tkInteger then begin
          hi := tokInt; NextToken;
        end else if (tokKind = tkString) and (length(tokStr) = 1) then begin
          hi := ord(tokStr[1]); NextToken;
        end else if tokKind = tkIdent then begin
          sym := LookupSym(tokStr);
          if (sym < 0) or (syms[sym].kind <> skConst) then
            Error('constant expected in set initializer');
          hi := syms[sym].offset;
          NextToken;
        end else
          Error('constant expected in set initializer');
      end else
        hi := lo;

      for i := lo to hi do begin
        if (i < 0) or (i > setHiBound) or (i > 255) then
          Error('set element out of range');
        bm[i div 8] := bm[i div 8] or (1 shl (i mod 8));
      end;

      if tokKind = tkComma then
        NextToken
      else
        break;
    until false;
  end;
  Expect(tkRBrack);

  for i := 0 to setSize - 1 do
    DataBufEmit(secData, bm[i]);
end;

procedure ParseBlock;
var
  savedFrameSize: longint;
  typDeclName: string;
  typDeclTyp, typDeclTypeIdx, typDeclSize, typDeclStrMax: longint;
  sym: longint;
  ci: longint;
  dataAddr: longint;
  initVal, initValTyp: longint;
  si: longint;
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
          if tokKind = tkColon then begin
            { Typed constant: const NAME : TYPE = INIT ; }
            NextToken;
            ParseTypeSpec(typDeclTyp, typDeclTypeIdx, typDeclSize, typDeclStrMax);
            Expect(tkEqual);
            sym := AddSym(typDeclName, skConst, typDeclTyp);
            syms[sym].typeIdx := typDeclTypeIdx;
            syms[sym].size := typDeclSize;
            syms[sym].strMax := typDeclStrMax;
            if typDeclTyp = tyArray then begin
              dataAddr := AllocDataAligned(typDeclSize, 4);
              EmitArrayInitializer(typDeclTypeIdx);
              syms[sym].offset := dataAddr;
            end else if typDeclTyp = tyRecord then begin
              dataAddr := AllocDataAligned(typDeclSize, 4);
              EmitRecordInitializer(typDeclTypeIdx);
              syms[sym].offset := dataAddr;
            end else if typDeclTyp = tySet then begin
              dataAddr := AllocDataAligned(typDeclSize, 4);
              EmitSetInitializer(typDeclTypeIdx);
              syms[sym].offset := dataAddr;
            end else if typDeclTyp = tyString then begin
              if tokKind <> tkString then
                Error('string constant expected');
              if length(tokStr) > typDeclStrMax then
                Error('string literal exceeds type capacity');
              dataAddr := AllocData(typDeclStrMax + 1);
              DataBufEmit(secData, byte(length(tokStr)));
              for si := 1 to length(tokStr) do
                DataBufEmit(secData, byte(ord(tokStr[si])));
              for si := length(tokStr) + 1 to typDeclStrMax do
                DataBufEmit(secData, 0);
              syms[sym].offset := dataAddr;
              NextToken;
            end else begin
              { Scalar typed const: store value directly in offset }
              EvalConstExpr(initVal, initValTyp);
              syms[sym].offset := initVal;
            end;
          end else begin
            Expect(tkEqual);
            EvalConstExpr(typDeclSize, typDeclTyp);
            sym := AddSym(typDeclName, skConst, typDeclTyp);
            syms[sym].offset := typDeclSize;
            if typDeclTyp = tyString then
              syms[sym].size := 256
            else
              syms[sym].size := 4;
          end;
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
        ResolvePendingPointers;
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
    { Stack overflow guard, emitted when stack checks are on. Runs BEFORE the
      subtraction, comparing against limit + frameSize rather than checking
      $sp afterwards.
      WAT: global.get $sp
           global.get $__heap_end
           i32.const <frameSize>
           i32.add
           i32.lt_u
           if
             unreachable
           end
      Checking afterwards looks simpler and is wrong: a frame large enough to
      carry $sp past zero wraps it to a huge unsigned value, which compares
      as above the limit and sails through. Checking first means $sp never
      wraps, and it is still valid at the trap, which makes the failure
      easier to read.
      Without any guard the stack walks down through the heap and the data
      segment, corrupting whatever it passes while the program carries on
      with wrong data. Only emitted when the function actually moves $sp: a
      frameless function cannot overflow it. }
    if optStackChecks then begin
      EmitGlobalGet(0);
      EmitGlobalGet(GlobalHeapEnd);
      EmitI32Const(curFrameSize);
      EmitOp(OpI32Add);
      EmitOp(OpI32LtU);
      EmitOp(OpIf); EmitOp(WasmVoid);
        EmitOp(OpUnreachable);
      EmitOp(OpEnd);
    end;

    EmitGlobalGet(0);
    EmitI32Const(curFrameSize);
    EmitOp(OpI32Sub);
    EmitGlobalSet(0);
  end;

  { Set display[curNestLevel] := $sp so nested procs can find this frame.
    Global index = curNestLevel + 1 (global 0 = $sp, globals 1..8 = display[0..7]). }
  EmitGlobalGet(0);  { $sp }
  EmitGlobalSet(curNestLevel + 1); { display[N] = global N+1 }

  { Copy structured value params into frame }
  for ci := 0 to numStructCopies - 1 do begin
    { dst = $sp + frameOffset }
    EmitGlobalGet(0);
    EmitI32Const(structCopyFrameOff[ci]);
    EmitOp(OpI32Add);
    { src = WASM local (holds pointer to caller's data) }
    EmitLocalGet(structCopyLocal[ci]);
    { size }
    EmitI32Const(structCopySize[ci]);
    EmitMemoryCopy;
    { Update WASM local to point to frame copy }
    EmitGlobalGet(0);
    EmitI32Const(structCopyFrameOff[ci]);
    EmitOp(OpI32Add);
    EmitLocalSet(structCopyLocal[ci]);
  end;
  numStructCopies := 0;

  { Spill var/const param pointers to frame for nested proc access }
  for ci := 0 to numVarParamSpills - 1 do begin
    EmitFramePtr(curNestLevel);
    EmitI32Const(varParamSpillFrameOff[ci]);
    EmitOp(OpI32Add);
    EmitLocalGet(varParamSpillLocal[ci]);
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

  { Frame balance check.
    display[N] holds this frame's base. The prologue set it from $sp after
    the allocation, so it is the entry $sp minus the frame size, and it
    survives recursion because a recursive call saves and restores it.
    WAT: global.get $sp
         global.get $display[N]
         i32.ne
         if
           unreachable
         end
    Nothing but a balanced call should have moved $sp between the prologue
    and here. The body does allocate scratch for string concat in const
    argument position and free it after the call, so this is a live check on
    that bookkeeping, not a placeholder for future features. }
  if optStackChecks then begin
    EmitGlobalGet(0);
    EmitGlobalGet(curNestLevel + 1); { display[N] = global N+1 }
    EmitOp(OpI32Ne);
    EmitOp(OpIf); EmitOp(WasmVoid);
      EmitOp(OpUnreachable);
    EmitOp(OpEnd);
  end;

  { Emit frame epilogue: $sp := display[N] + frameSize.
    Restoring from the recorded frame base rather than adding frameSize to
    whatever $sp happens to hold makes an unbalanced allocation inside the
    body self-healing at return. Without it a single leaked allocation
    desynchronizes $sp for the rest of the program, and the damage shows up
    somewhere unrelated. Same instruction count as the relative form. }
  if curFrameSize > 0 then begin
    EmitGlobalGet(curNestLevel + 1); { display[N] = global N+1 }
    EmitI32Const(curFrameSize);
    EmitOp(OpI32Add);
    EmitGlobalSet(0);
  end;

  { Restore display[N] after the frame is released (procedures only) }
  if displayLocalIdx >= 0 then begin
    EmitLocalGet(displayLocalIdx);
    EmitGlobalSet(curNestLevel + 1); { display[N] = global N+1 }
  end;

  curFrameSize := savedFrameSize;
end;

{ ---- WASM module assembly ---- }

{** Append one byte to the final output buffer (the assembled .wasm file). }
procedure WriteOutputByte(b: byte);
begin
  CodeBufEmit(outBuf, b);
end;

{** Append a ULEB128-encoded integer to the final output buffer. }
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

{** Append a length-prefixed WASM name (ULEB128 length + UTF-8 bytes). }
procedure WriteOutputString(const s: string);
var i: longint;
begin
  WriteOutputULEB128(length(s));
  for i := 1 to length(s) do
    WriteOutputByte(ord(s[i]));
end;

{** Emit a WASM section from a small buffer: section id, ULEB128 size,
  then payload bytes. Skipped if buf is empty. }
procedure WriteSmallSection(id: byte; var buf: TSmallBuf);
var i: longint;
begin
  if buf.len = 0 then exit;
  WriteOutputByte(id);
  WriteOutputULEB128(buf.len);
  for i := 0 to buf.len - 1 do
    WriteOutputByte(buf.data[i]);
end;

{** Emit a WASM section from a (large) code buffer. Same shape as
  WriteSmallSection; used for code and data sections. }
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

{** Build the import section from the imports table (WASI functions). }
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

{** Build the function section: type index for each defined function.

  Slots 0..22 are reserved for the compiler-generated runtime helpers
  (_start, __write_int, __read_int, string ops, checked arithmetic,
  set ops, etc.). Slots 26+ are user-defined functions. }
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
  { Slot 23: __nil_check uses type i32 -> i32 (always present) }
  SmallEmitULEB128(secFunc, TypeI32I32);
  { Slot 24: __heap_alloc uses type i32 -> i32 (always present) }
  SmallEmitULEB128(secFunc, TypeI32I32);
  { Slot 25: __heap_free uses type i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32Void);
  { Slots 26+: User-defined functions (skip imports) }
  for i := 0 to numFuncs - 1 do
    if funcs[i].bodyStart <> -2 then
      SmallEmitULEB128(secFunc, funcs[i].typeidx);
end;

{** Build the memory section. Declares a single linear memory with
  pages = max(optMemPages, ceil(dataPos/64KiB)) and max optMaxMemPages. }
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

{** Build the global section.

  Globals: $sp (stack pointer, mutable i32) + 8 display[] frame
  pointers for nested-scope access + immutable __version encoding
  CalVer as YY*65536 + MM*256 + patch. }
procedure AssembleGlobalSection;
const
  MaxDisplayDepth = 8;
var
  i: longint;
begin
  SmallBufInit(secGlobal);
  SmallBufEmit(secGlobal, 1 + MaxDisplayDepth + 2); { $sp + 8 display + __version + __heap_end }
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
  { Global 10: __heap_end — the first address the stack must not reach, and
    the address the next heap block will be carved from. One global serves
    both because they are the same number: the heap grows up from the data
    segment and the stack grows down from the top of memory, so the boundary
    between them is a single value.

    It starts at the data segment's high-water mark and moves up as the heap
    grows. dataPos is final by the time this section is assembled, which is
    why this lives in a global rather than as an immediate in each prologue:
    frame code is emitted long before the last string literal is allocated.

    Mutable since the heap arrived. While there was no heap it was constant,
    and the earlier comment said immutable as though that were a property
    rather than a consequence. }
  SmallBufEmit(secGlobal, WasmI32);  { type: i32 }
  SmallBufEmit(secGlobal, 1);        { mutable }
  SmallBufEmit(secGlobal, OpI32Const);
  SmallEmitSLEB128(secGlobal, dataPos);
  SmallBufEmit(secGlobal, OpEnd);
end;

{** Build the export section. Always exports _start (entry point),
  memory, and __version global; then any user EXPORT directives. }
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

{** Emit an opcode into the helper-function code buffer.
  Mirror of EmitOp but targets helperCode, used while building
  compiler-generated runtime helpers like __write_int. }
procedure EmitHelper(op: byte);
{$IFDEF PEEPHOLE}
var start: longint;
{$ENDIF}
begin
  {$IFDEF PEEPHOLE}
  start := helperCode.len;
  {$ENDIF}
  CodeBufEmit(helperCode, op);
  {$IFDEF PEEPHOLE}
  if op = OpI32Eqz then
    FinishOp(helperCode, start)
  else
    InvalidateOp(helperCode);
  {$ENDIF}
end;

{** Emit i32.const into the helper code buffer.
  ;; WAT: i32.const <value> }
procedure EmitHelperI32Const(value: longint);
begin
  CodeBufEmit(helperCode, OpI32Const);
  EmitSLEB128Fix(helperCode, value);
  InvalidateOp(helperCode);
end;

{** Emit a raw ULEB128 into the helper code buffer. }
procedure EmitHelperULEB128(value: longint);
begin
  EmitULEB128(helperCode, value);
end;

{** Emit global.get <idx> into the helper code buffer.
  ;; WAT: global.get <idx> }
procedure EmitHelperGlobalGet(idx: longint);
var start: longint;
begin
  start := helperCode.len;
  CodeBufEmit(helperCode, OpGlobalGet);
  EmitULEB128(helperCode, idx);
  FinishOp(helperCode, start);
end;

{** Emit global.set <idx> into the helper code buffer.
  ;; WAT: global.set <idx> }
procedure EmitHelperGlobalSet(idx: longint);
var start: longint;
begin
  start := helperCode.len;
  CodeBufEmit(helperCode, OpGlobalSet);
  EmitULEB128(helperCode, idx);
  FinishOp(helperCode, start);
end;

{** Emit i32.load with the given alignment and offset. }
procedure EmitHelperI32Load(align, offset: longint);
begin
  EmitHelper(OpI32Load);
  EmitHelperULEB128(align);
  EmitHelperULEB128(offset);
end;

{** Emit i32.store with the given alignment and offset. }
procedure EmitHelperI32Store(align, offset: longint);
begin
  EmitHelper(OpI32Store);
  EmitHelperULEB128(align);
  EmitHelperULEB128(offset);
end;

{** Emit local.get <idx> into the helper code buffer.
  ;; WAT: local.get <idx> }
procedure EmitHelperLocalGet(idx: longint);
var start: longint;
begin
  start := helperCode.len;
  CodeBufEmit(helperCode, OpLocalGet);
  EmitULEB128(helperCode, idx);
  FinishOp(helperCode, start);
end;

{** Emit local.set <idx> into the helper code buffer.
  ;; WAT: local.set <idx> }
procedure EmitHelperLocalSet(idx: longint);
var start: longint;
begin
  start := helperCode.len;
  CodeBufEmit(helperCode, OpLocalSet);
  EmitULEB128(helperCode, idx);
  FinishOp(helperCode, start);
end;

{** Emit local.tee <idx> into the helper code buffer.
  ;; WAT: local.tee <idx> }
procedure EmitHelperLocalTee(idx: longint);
var start: longint;
begin
  start := helperCode.len;
  CodeBufEmit(helperCode, OpLocalTee);
  EmitULEB128(helperCode, idx);
  FinishOp(helperCode, start);
end;

{** Emit a call instruction into the helper code buffer.
  ;; WAT: call <funcIdx> }
procedure EmitHelperCall(funcIdx: longint);
begin
  CodeBufEmit(helperCode, OpCall);
  EmitULEB128(helperCode, funcIdx);
  InvalidateOp(helperCode);
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
  EmitHelperLocalSet(1);

  (* sign = 1.  Local 2 holds a multiplier, not a flag: the value is never
     negated, because 0 - (-2147483648) overflows back to itself and the
     digit loop would then produce negative digits. *)
  EmitHelperI32Const(1);
  EmitHelperLocalSet(2);

  (* if value < 0 then sign = -1.  value stays negative. *)
  EmitHelperLocalGet(0);
  EmitHelperI32Const(0);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(-1);
    EmitHelperLocalSet(2);
  EmitHelper(OpEnd);

  (* if value == 0: special case *)
  EmitHelperLocalGet(0);
  EmitHelper(OpI32Eqz);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    (* store '0' at pos *)
    EmitHelperLocalGet(1);
    EmitHelperI32Const(ord('0'));
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
    (* pos-- *)
    EmitHelperLocalGet(1);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Sub);
    EmitHelperLocalSet(1);
  EmitHelper(OpElse);
    (* loop: extract digits *)
    EmitHelper(OpLoop); EmitHelper(WasmVoid);
      (* digit = (value % 10) * sign + '0'.  i32.rem_s follows the sign of
         the dividend, so the product is always 0..9 for either sign. *)
      EmitHelperLocalGet(1);  (* pos = store address *)
      EmitHelperLocalGet(0);  (* value *)
      EmitHelperI32Const(10);
      EmitHelper(OpI32RemS);
      EmitHelperLocalGet(2);  (* sign *)
      EmitHelper(OpI32Mul);
      EmitHelperI32Const(ord('0'));
      EmitHelper(OpI32Add);
      EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

      (* value = value / 10 *)
      EmitHelperLocalGet(0);
      EmitHelperI32Const(10);
      EmitHelper(OpI32DivS);
      EmitHelperLocalSet(0);

      (* pos-- *)
      EmitHelperLocalGet(1);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Sub);
      EmitHelperLocalSet(1);

      (* if value != 0: continue *)
      EmitHelperLocalGet(0);
      EmitHelperI32Const(0);
      EmitHelper(OpI32Ne);
      EmitHelper(OpBrIf); EmitHelperULEB128(0);
    EmitHelper(OpEnd); (* end loop *)
  EmitHelper(OpEnd); (* end if/else *)

  (* if negative (sign < 0): store '-' *)
  EmitHelperLocalGet(2);
  EmitHelperI32Const(0);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperLocalGet(1);
    EmitHelperI32Const(ord('-'));
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelperLocalGet(1);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Sub);
    EmitHelperLocalSet(1);
  EmitHelper(OpEnd);

  (* pos++ to point to first character *)
  EmitHelperLocalGet(1);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Add);
  EmitHelperLocalSet(1);

  (* Set up iovec: buf = pos, len = intbuf+20 - pos *)
  EmitHelperI32Const(addrIovec);
  EmitHelperLocalGet(1);
  EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);

  EmitHelperI32Const(addrIovec + 4);
  EmitHelperI32Const(addrIntBuf + 20);
  EmitHelperLocalGet(1);
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

procedure BuildHeapAllocHelper;
(** Build __heap_alloc(size: i32) -> i32 into helperCode.

  A first-fit free list over blocks carved from the space between the data
  segment and the stack. Each block carries an 8-byte header:

      [ size: i32 ][ next: i32 ][ payload ... ]

  `size` is the whole block including the header, rounded up to 8 so every
  payload is 8-aligned. `next` links free blocks; it is dead in a block that
  is in use.

  Deliberately not done: no splitting of an oversized free block, and no
  coalescing of adjacent free ones. A program that allocates and frees the
  same shapes, which is what a list or a tree does, reuses its blocks exactly.
  A program that allocates many sizes will fragment, and that is the
  programmer's problem — stated in the language reference rather than papered
  over with an allocator nobody asked for.

  Parameters:
    local 0 = requested payload size
  Locals:
    local 1 = total, the rounded block size including the header
    local 2 = prev, the free-list predecessor of cur
    local 3 = cur, the free block being examined
    local 4 = blk, the block being carved when the free list has nothing
*)
begin
  CodeBufInit(helperCode);

  (* total = (size + 8 + 7) and not 7 *)
  EmitHelperLocalGet(0);
  EmitHelperI32Const(15);
  EmitHelper(OpI32Add);
  EmitHelperI32Const(-8);
  EmitHelper(OpI32And);
  EmitHelperLocalSet(1);

  (* prev = 0; cur = free list head *)
  EmitHelperI32Const(0);
  EmitHelperLocalSet(2);
  EmitHelperI32Const(addrHeapFree);
  EmitHelperI32Load(2, 0);
  EmitHelperLocalSet(3);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);   (* label 1: no block found *)
  EmitHelper(OpLoop);  EmitHelper(WasmVoid);   (* label 0: walk *)

    (* if cur = 0 then leave the loop and carve a new block *)
    EmitHelperLocalGet(3);
    EmitHelper(OpI32Eqz);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* if block size >= total then take it *)
    EmitHelperLocalGet(3);
    EmitHelperI32Load(2, 0);
    EmitHelperLocalGet(1);
    EmitHelper(OpI32GeU);
    EmitHelper(OpIf); EmitHelper(WasmVoid);

      (* unlink: head or predecessor takes cur's successor *)
      EmitHelperLocalGet(2);
      EmitHelper(OpI32Eqz);
      EmitHelper(OpIf); EmitHelper(WasmVoid);
        EmitHelperI32Const(addrHeapFree);
        EmitHelperLocalGet(3);
        EmitHelperI32Load(2, 4);
        EmitHelperI32Store(2, 0);
      EmitHelper(OpElse);
        EmitHelperLocalGet(2);
        EmitHelperLocalGet(3);
        EmitHelperI32Load(2, 4);
        EmitHelperI32Store(2, 4);
      EmitHelper(OpEnd);

      (* return cur + 8 *)
      EmitHelperLocalGet(3);
      EmitHelperI32Const(8);
      EmitHelper(OpI32Add);
      EmitHelper(OpReturn);
    EmitHelper(OpEnd);

    (* prev = cur; cur = cur^.next *)
    EmitHelperLocalGet(3);
    EmitHelperLocalSet(2);
    EmitHelperLocalGet(3);
    EmitHelperI32Load(2, 4);
    EmitHelperLocalSet(3);
    EmitHelper(OpBr); EmitHelperULEB128(0);

  EmitHelper(OpEnd);   (* end loop *)
  EmitHelper(OpEnd);   (* end block *)

  (* Carve a new block at the heap end. *)
  EmitHelperGlobalGet(GlobalHeapEnd);
  EmitHelperLocalSet(4);

  (* The heap must not reach the stack. Unsigned compare, and > rather than
     >=, so a heap that grows exactly up to $sp is still legal. This is the
     other half of the prologue's stack guard: one of them catches growth
     from each side. *)
  EmitHelperLocalGet(4);
  EmitHelperLocalGet(1);
  EmitHelper(OpI32Add);
  EmitHelperGlobalGet(0);
  EmitHelper(OpI32GtU);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpUnreachable);
  EmitHelper(OpEnd);

  (* Move the heap end, which also raises the stack's floor. *)
  EmitHelperLocalGet(4);
  EmitHelperLocalGet(1);
  EmitHelper(OpI32Add);
  EmitHelperGlobalSet(GlobalHeapEnd);

  (* blk^.size = total; return blk + 8 *)
  EmitHelperLocalGet(4);
  EmitHelperLocalGet(1);
  EmitHelperI32Store(2, 0);
  EmitHelperLocalGet(4);
  EmitHelperI32Const(8);
  EmitHelper(OpI32Add);
end;

procedure BuildHeapFreeHelper;
(** Build __heap_free(addr: i32) into helperCode.

  Pushes the block onto the front of the free list. Nothing is merged and
  nothing is returned to the heap end, so freeing the most recent allocation
  does not lower the heap.

  Parameters:
    local 0 = payload address
  Locals:
    local 1 = blk, the block header address
*)
begin
  CodeBufInit(helperCode);

  (* blk = addr - 8 *)
  EmitHelperLocalGet(0);
  EmitHelperI32Const(8);
  EmitHelper(OpI32Sub);
  EmitHelperLocalSet(1);

  (* blk^.next = head *)
  EmitHelperLocalGet(1);
  EmitHelperI32Const(addrHeapFree);
  EmitHelperI32Load(2, 0);
  EmitHelperI32Store(2, 4);

  (* head = blk *)
  EmitHelperI32Const(addrHeapFree);
  EmitHelperLocalGet(1);
  EmitHelperI32Store(2, 0);
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
  EmitHelperLocalGet(0);
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
  EmitHelperLocalGet(1);  { fd }
  EmitHelperI32Const(addrIovec);
  EmitHelperI32Const(1);
  EmitHelperI32Const(addrNwritten);
  EmitHelperCall(fdw);
  EmitHelper(OpDrop);
end;

procedure BuildIntToStrHelper;
(** Build __int_to_str(value: i32, dest: i32) function body into helperCode.
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
  EmitHelperLocalSet(2);

  (* sign = 1.  Local 3 is a multiplier, not a flag: negating the value
     would overflow for -2147483648.  Same fix as __write_int. *)
  EmitHelperI32Const(1);
  EmitHelperLocalSet(3);

  (* if value < 0 then sign = -1.  value stays negative. *)
  EmitHelperLocalGet(0);
  EmitHelperI32Const(0);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(-1);
    EmitHelperLocalSet(3);
  EmitHelper(OpEnd);

  (* if value == 0: special case *)
  EmitHelperLocalGet(0);
  EmitHelper(OpI32Eqz);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperLocalGet(2);
    EmitHelperI32Const(ord('0'));
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelperLocalGet(2);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Sub);
    EmitHelperLocalSet(2);
  EmitHelper(OpElse);
    (* loop: extract digits right to left *)
    EmitHelper(OpLoop); EmitHelper(WasmVoid);
      (* digit = (value % 10) * sign + '0' *)
      EmitHelperLocalGet(2);
      EmitHelperLocalGet(0);
      EmitHelperI32Const(10);
      EmitHelper(OpI32RemS);
      EmitHelperLocalGet(3);
      EmitHelper(OpI32Mul);
      EmitHelperI32Const(ord('0'));
      EmitHelper(OpI32Add);
      EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

      EmitHelperLocalGet(0);
      EmitHelperI32Const(10);
      EmitHelper(OpI32DivS);
      EmitHelperLocalSet(0);

      EmitHelperLocalGet(2);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Sub);
      EmitHelperLocalSet(2);

      EmitHelperLocalGet(0);
      EmitHelperI32Const(0);
      EmitHelper(OpI32Ne);
      EmitHelper(OpBrIf); EmitHelperULEB128(0);
    EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* if negative (sign < 0): store '-' *)
  EmitHelperLocalGet(3);
  EmitHelperI32Const(0);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperLocalGet(2);
    EmitHelperI32Const(ord('-'));
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelperLocalGet(2);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Sub);
    EmitHelperLocalSet(2);
  EmitHelper(OpEnd);

  (* pos++ to point to first character *)
  EmitHelperLocalGet(2);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Add);
  EmitHelperLocalSet(2);

  (* len = intbuf + 20 - pos *)
  EmitHelperI32Const(addrIntBuf + 20);
  EmitHelperLocalGet(2);
  EmitHelper(OpI32Sub);
  EmitHelperLocalSet(4);

  (* store length byte at dest *)
  EmitHelperLocalGet(1);
  EmitHelperLocalGet(4);
  EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

  (* memory.copy dest+1, pos, len *)
  EmitHelperLocalGet(1);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Add);
  EmitHelperLocalGet(2);
  EmitHelperLocalGet(4);
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
  EmitHelperLocalSet(0);

  (* negative = 0 *)
  EmitHelperI32Const(0);
  EmitHelperLocalSet(1);

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
      EmitHelperLocalGet(0);
      EmitHelper(OpReturn);
    EmitHelper(OpEnd);

    (* byte_val = readbuf[0] *)
    EmitHelperI32Const(addrReadBuf);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelperLocalSet(2);

    (* if byte_val == ' ' or byte_val == 9 or byte_val == 10 or byte_val == 13: continue *)
    EmitHelperLocalGet(2);
    EmitHelperI32Const(32);   { space }
    EmitHelper(OpI32Eq);
    EmitHelperLocalGet(2);
    EmitHelperI32Const(9);    { tab }
    EmitHelper(OpI32Eq);
    EmitHelper(OpI32Or);
    EmitHelperLocalGet(2);
    EmitHelperI32Const(10);   { LF }
    EmitHelper(OpI32Eq);
    EmitHelper(OpI32Or);
    EmitHelperLocalGet(2);
    EmitHelperI32Const(13);   { CR }
    EmitHelper(OpI32Eq);
    EmitHelper(OpI32Or);
    EmitHelper(OpBrIf); EmitHelperULEB128(0);  { continue loop }
  EmitHelper(OpEnd); (* end whitespace loop *)

  (* --- Phase 2: Check for sign --- *)
  (* if byte_val == '-' *)
  EmitHelperLocalGet(2);
  EmitHelperI32Const(ord('-'));
  EmitHelper(OpI32Eq);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(1);
    EmitHelperLocalSet(1);  { negative = 1 }
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
    EmitHelperLocalSet(2);
  EmitHelper(OpElse);
    (* if byte_val == '+', skip it and read next byte *)
    EmitHelperLocalGet(2);
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
      EmitHelperLocalSet(2);
    EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* --- Phase 3: Parse digits --- *)
  (* byte_val is now the first digit (or non-digit if malformed input).
     Loop: while byte_val >= '0' and byte_val <= '9' *)
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* Check: byte_val >= '0' *)
    EmitHelperLocalGet(2);
    EmitHelperI32Const(ord('0'));
    EmitHelper(OpI32GeS);
    (* Check: byte_val <= '9' *)
    EmitHelperLocalGet(2);
    EmitHelperI32Const(ord('9'));
    EmitHelper(OpI32LeS);
    (* Both conditions *)
    EmitHelper(OpI32And);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      (* result = result * 10 + (byte_val - '0') *)
      EmitHelperLocalGet(0);
      EmitHelperI32Const(10);
      EmitHelper(OpI32Mul);
      EmitHelperLocalGet(2);
      EmitHelperI32Const(ord('0'));
      EmitHelper(OpI32Sub);
      EmitHelper(OpI32Add);
      EmitHelperLocalSet(0);

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
        EmitHelperLocalSet(2);
      EmitHelper(OpElse);
        EmitHelperI32Const(addrReadBuf);
        EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
        EmitHelperLocalSet(2);
      EmitHelper(OpEnd);

      EmitHelper(OpBr); EmitHelperULEB128(1);  { continue outer loop }
    EmitHelper(OpEnd); (* end if digit *)
  EmitHelper(OpEnd); (* end digit loop *)

  (* --- Phase 4: Apply sign and return --- *)
  EmitHelperLocalGet(1);  { negative flag }
  EmitHelper(OpIf); EmitHelper(WasmI32);
    EmitHelperI32Const(0);
    EmitHelperLocalGet(0);
    EmitHelper(OpI32Sub);
  EmitHelper(OpElse);
    EmitHelperLocalGet(0);
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
  EmitHelperLocalGet(2);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelperLocalSet(3);

  (* if len > max_len then len := max_len *)
  EmitHelperLocalGet(3);
  EmitHelperLocalGet(1);
  EmitHelper(OpI32GtU);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperLocalGet(1);
    EmitHelperLocalSet(3);
  EmitHelper(OpEnd);

  (* dst[0] := len *)
  EmitHelperLocalGet(0);
  EmitHelperLocalGet(3);
  EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelperLocalSet(4);

  (* while i < len do begin *)
  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    EmitHelperLocalGet(4);
    EmitHelperLocalGet(3);
    EmitHelper(OpI32GeU);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);  { break if i >= len }

    (* dst[i+1] := src[i+1] *)
    EmitHelperLocalGet(0);
    EmitHelperLocalGet(4);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);       { dst + i + 1 }

    EmitHelperLocalGet(2);
    EmitHelperLocalGet(4);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);       { src + i + 1 }
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);

    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

    (* i := i + 1 *)
    EmitHelperLocalGet(4);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(4);

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
  EmitHelperLocalGet(0);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Add);
  EmitHelper(OpI32Store); EmitHelperULEB128(2); EmitHelperULEB128(0);

  (* iovec.len = addr[0]  (length byte) *)
  EmitHelperI32Const(addrIovec + 4);
  EmitHelperLocalGet(0);
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
  EmitHelperLocalGet(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelperLocalSet(2);

  EmitHelperLocalGet(1);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelperLocalGet(2);
  EmitHelper(OpI32LtU);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperLocalGet(1);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelperLocalSet(2);
  EmitHelper(OpEnd);

  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelperLocalSet(3);

  (* compare characters loop *)
  EmitHelper(OpBlock); EmitHelper(WasmVoid);   { block $break }
  EmitHelper(OpLoop); EmitHelper(WasmVoid);    { loop $continue }
    (* if i >= minLen then break *)
    EmitHelperLocalGet(3);
    EmitHelperLocalGet(2);
    EmitHelper(OpI32GeU);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* ca = a[i+1] *)
    EmitHelperLocalGet(0);
    EmitHelperLocalGet(3);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelperLocalSet(4);

    (* cb = b[i+1] *)
    EmitHelperLocalGet(1);
    EmitHelperLocalGet(3);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelperLocalSet(5);

    (* if ca < cb then return -1 *)
    EmitHelperLocalGet(4);
    EmitHelperLocalGet(5);
    EmitHelper(OpI32LtU);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      EmitHelperI32Const(-1);
      EmitHelper(OpReturn);
    EmitHelper(OpEnd);

    (* if ca > cb then return 1 *)
    EmitHelperLocalGet(4);
    EmitHelperLocalGet(5);
    EmitHelper(OpI32GtU);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      EmitHelperI32Const(1);
      EmitHelper(OpReturn);
    EmitHelper(OpEnd);

    (* i := i + 1 *)
    EmitHelperLocalGet(3);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(3);

    EmitHelper(OpBr); EmitHelperULEB128(0);  { continue loop }
  EmitHelper(OpEnd);  { end loop }
  EmitHelper(OpEnd);  { end block }

  (* All common chars equal — compare lengths: a[0] - b[0], clamped to -1/0/1 *)
  EmitHelperLocalGet(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelperLocalGet(1);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelper(OpI32Sub);
  (* clamp: if result > 0 then 1, if < 0 then -1, else 0 *)
  EmitHelperLocalSet(4);  { reuse ca as temp }
  EmitHelperLocalGet(4);
  EmitHelperI32Const(0);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper($7F);  { i32 result }
    EmitHelperI32Const(1);
  EmitHelper(OpElse);
    EmitHelperLocalGet(4);
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
  EmitHelperLocalSet(2);

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
    EmitHelperLocalGet(2);
    EmitHelperLocalGet(1);
    EmitHelper(OpI32LtU);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      (* addr[i+1] := readbuf[0] *)
      EmitHelperLocalGet(0);
      EmitHelperLocalGet(2);
      EmitHelper(OpI32Add);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Add);       { addr + i + 1 }
      EmitHelperI32Const(addrReadBuf);
      EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
      EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

      (* i := i + 1 *)
      EmitHelperLocalGet(2);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Add);
      EmitHelperLocalSet(2);
    EmitHelper(OpEnd);

    EmitHelper(OpBr); EmitHelperULEB128(0);  { continue loop }
  EmitHelper(OpEnd);  { end loop }
  EmitHelper(OpEnd);  { end block }

  (* addr[0] := i (set length byte) *)
  EmitHelperLocalGet(0);
  EmitHelperLocalGet(2);
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
  EmitHelperLocalGet(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelperLocalSet(3);

  (* srcLen := src[0] *)
  EmitHelperLocalGet(2);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelperLocalSet(4);

  (* avail := maxlen - curLen; if srcLen > avail then srcLen := avail *)
  EmitHelperLocalGet(4);
  EmitHelperLocalGet(1);
  EmitHelperLocalGet(3);
  EmitHelper(OpI32Sub);
  EmitHelper(OpI32GtU);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperLocalGet(1);
    EmitHelperLocalGet(3);
    EmitHelper(OpI32Sub);
    EmitHelperLocalSet(4);
  EmitHelper(OpEnd);

  (* dst[0] := curLen + srcLen *)
  EmitHelperLocalGet(0);
  EmitHelperLocalGet(3);
  EmitHelperLocalGet(4);
  EmitHelper(OpI32Add);
  EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

  (* Copy src[1..srcLen] to dst[curLen+1..curLen+srcLen] *)
  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelperLocalSet(5);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);   { block $break }
  EmitHelper(OpLoop); EmitHelper(WasmVoid);    { loop $cont }
    (* if i >= srcLen then break *)
    EmitHelperLocalGet(5);
    EmitHelperLocalGet(4);
    EmitHelper(OpI32GeU);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* dst[curLen + i + 1] := src[i + 1] *)
    EmitHelperLocalGet(0);
    EmitHelperLocalGet(3);
    EmitHelper(OpI32Add);
    EmitHelperLocalGet(5);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalGet(2);
    EmitHelperLocalGet(5);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

    (* i := i + 1 *)
    EmitHelperLocalGet(5);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(5);

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
  EmitHelperLocalGet(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelperLocalSet(4);

  (* if idx < 1 then idx := 1 *)
  EmitHelperLocalGet(1);
  EmitHelperI32Const(1);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(1);
    EmitHelperLocalSet(1);
  EmitHelper(OpEnd);

  (* if idx > srcLen then count := 0 *)
  EmitHelperLocalGet(1);
  EmitHelperLocalGet(4);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(0);
    EmitHelperLocalSet(2);
  EmitHelper(OpEnd);

  (* if idx + count - 1 > srcLen then count := srcLen - idx + 1 *)
  EmitHelperLocalGet(1);
  EmitHelperLocalGet(2);
  EmitHelper(OpI32Add);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Sub);
  EmitHelperLocalGet(4);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperLocalGet(4);
    EmitHelperLocalGet(1);
    EmitHelper(OpI32Sub);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(2);
  EmitHelper(OpEnd);

  (* if count < 0 then count := 0 *)
  EmitHelperLocalGet(2);
  EmitHelperI32Const(0);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(0);
    EmitHelperLocalSet(2);
  EmitHelper(OpEnd);

  (* if count > 255 then count := 255 *)
  EmitHelperLocalGet(2);
  EmitHelperI32Const(255);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(255);
    EmitHelperLocalSet(2);
  EmitHelper(OpEnd);

  (* dst[0] := count *)
  EmitHelperLocalGet(3);
  EmitHelperLocalGet(2);
  EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

  (* copy src[idx..idx+count-1] to dst[1..count] *)
  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelperLocalSet(5);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* if i >= count then break *)
    EmitHelperLocalGet(5);
    EmitHelperLocalGet(2);
    EmitHelper(OpI32GeS);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* dst[i + 1] := src[idx + i] *)
    EmitHelperLocalGet(3);
    EmitHelperLocalGet(5);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalGet(0);
    EmitHelperLocalGet(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalGet(5);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

    (* i := i + 1 *)
    EmitHelperLocalGet(5);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(5);

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
  EmitHelperLocalGet(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelperLocalSet(2);

  (* sLen := s[0] *)
  EmitHelperLocalGet(1);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelperLocalSet(3);

  (* if subLen = 0 then return 0 *)
  EmitHelperLocalGet(2);
  EmitHelper(OpI32Eqz);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(0);
    EmitHelper(OpReturn);
  EmitHelper(OpEnd);

  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelperLocalSet(4);

  (* outer loop: for i := 0 to sLen - subLen *)
  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* if i > sLen - subLen then break *)
    EmitHelperLocalGet(4);
    EmitHelperLocalGet(3);
    EmitHelperLocalGet(2);
    EmitHelper(OpI32Sub);
    EmitHelper(OpI32GtS);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* matched := 1; j := 0 *)
    EmitHelperI32Const(1);
    EmitHelperLocalSet(6);
    EmitHelperI32Const(0);
    EmitHelperLocalSet(5);

    (* inner loop: compare sub[j+1] with s[i+j+1] *)
    EmitHelper(OpBlock); EmitHelper(WasmVoid);
    EmitHelper(OpLoop); EmitHelper(WasmVoid);
      (* if j >= subLen then break inner *)
      EmitHelperLocalGet(5);
      EmitHelperLocalGet(2);
      EmitHelper(OpI32GeS);
      EmitHelper(OpBrIf); EmitHelperULEB128(1);

      (* if s[i+j+1] <> sub[j+1] then matched := 0; break inner *)
      EmitHelperLocalGet(1);
      EmitHelperLocalGet(4);
      EmitHelper(OpI32Add);
      EmitHelperLocalGet(5);
      EmitHelper(OpI32Add);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Add);
      EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
      EmitHelperLocalGet(0);
      EmitHelperLocalGet(5);
      EmitHelper(OpI32Add);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Add);
      EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
      EmitHelper(OpI32Ne);
      EmitHelper(OpIf); EmitHelper(WasmVoid);
        EmitHelperI32Const(0);
        EmitHelperLocalSet(6);
        EmitHelper(OpBr); EmitHelperULEB128(2); { break inner block }
      EmitHelper(OpEnd);

      (* j := j + 1 *)
      EmitHelperLocalGet(5);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Add);
      EmitHelperLocalSet(5);

      EmitHelper(OpBr); EmitHelperULEB128(0); { continue inner loop }
    EmitHelper(OpEnd); { end inner loop }
    EmitHelper(OpEnd); { end inner block }

    (* if matched then return i + 1 *)
    EmitHelperLocalGet(6);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      EmitHelperLocalGet(4);
      EmitHelperI32Const(1);
      EmitHelper(OpI32Add);
      EmitHelper(OpReturn);
    EmitHelper(OpEnd);

    (* i := i + 1 *)
    EmitHelperLocalGet(4);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(4);

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
  EmitHelperLocalGet(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelperLocalSet(3);

  (* if idx < 1 or idx > sLen then exit — nothing to delete *)
  EmitHelperLocalGet(1);
  EmitHelperI32Const(1);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpReturn);
  EmitHelper(OpEnd);
  EmitHelperLocalGet(1);
  EmitHelperLocalGet(3);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpReturn);
  EmitHelper(OpEnd);

  (* if count <= 0 then exit *)
  EmitHelperLocalGet(2);
  EmitHelperI32Const(0);
  EmitHelper(OpI32LeS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpReturn);
  EmitHelper(OpEnd);

  (* clamp: if idx + count - 1 > sLen then count := sLen - idx + 1 *)
  EmitHelperLocalGet(1);
  EmitHelperLocalGet(2);
  EmitHelper(OpI32Add);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Sub);
  EmitHelperLocalGet(3);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperLocalGet(3);
    EmitHelperLocalGet(1);
    EmitHelper(OpI32Sub);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(2);
  EmitHelper(OpEnd);

  (* tailStart := idx + count (1-based byte position of first char after deleted region) *)
  EmitHelperLocalGet(1);
  EmitHelperLocalGet(2);
  EmitHelper(OpI32Add);
  EmitHelperLocalSet(5);

  (* newLen := sLen - count *)
  EmitHelperLocalGet(3);
  EmitHelperLocalGet(2);
  EmitHelper(OpI32Sub);
  EmitHelperLocalSet(6);

  (* shift tail chars left: s[idx..newLen] := s[tailStart..sLen] *)
  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelperLocalSet(4);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* if tailStart + i > sLen then break *)
    EmitHelperLocalGet(5);
    EmitHelperLocalGet(4);
    EmitHelper(OpI32Add);
    EmitHelperLocalGet(3);
    EmitHelper(OpI32GtS);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* s[idx + i] := s[tailStart + i] — these are 1-based byte positions *)
    EmitHelperLocalGet(0);
    EmitHelperLocalGet(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalGet(4);
    EmitHelper(OpI32Add);
    EmitHelperLocalGet(0);
    EmitHelperLocalGet(5);
    EmitHelper(OpI32Add);
    EmitHelperLocalGet(4);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

    (* i := i + 1 *)
    EmitHelperLocalGet(4);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(4);

    EmitHelper(OpBr); EmitHelperULEB128(0);
  EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* s[0] := newLen *)
  EmitHelperLocalGet(0);
  EmitHelperLocalGet(6);
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
  EmitHelperLocalGet(0);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelperLocalSet(3);

  (* dstLen := dst[0] *)
  EmitHelperLocalGet(1);
  EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
  EmitHelperLocalSet(4);

  (* if srcLen = 0 then exit *)
  EmitHelperLocalGet(3);
  EmitHelper(OpI32Eqz);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelper(OpReturn);
  EmitHelper(OpEnd);

  (* clamp idx: if idx < 1 then idx := 1 *)
  EmitHelperLocalGet(2);
  EmitHelperI32Const(1);
  EmitHelper(OpI32LtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(1);
    EmitHelperLocalSet(2);
  EmitHelper(OpEnd);

  (* if idx > dstLen + 1 then idx := dstLen + 1 *)
  EmitHelperLocalGet(2);
  EmitHelperLocalGet(4);
  EmitHelperI32Const(1);
  EmitHelper(OpI32Add);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperLocalGet(4);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(2);
  EmitHelper(OpEnd);

  (* newLen := dstLen + srcLen; clamp to 255 *)
  EmitHelperLocalGet(4);
  EmitHelperLocalGet(3);
  EmitHelper(OpI32Add);
  EmitHelperLocalSet(5);
  EmitHelperLocalGet(5);
  EmitHelperI32Const(255);
  EmitHelper(OpI32GtS);
  EmitHelper(OpIf); EmitHelper(WasmVoid);
    EmitHelperI32Const(255);
    EmitHelperLocalSet(5);
    (* also clamp srcLen so we don't overflow *)
    EmitHelperI32Const(255);
    EmitHelperLocalGet(4);
    EmitHelper(OpI32Sub);
    EmitHelperLocalSet(3);
  EmitHelper(OpEnd);

  (* shift tail right: dst[idx+srcLen..newLen] := dst[idx..dstLen] *)
  (* iterate from dstLen down to idx to avoid overlap issues *)
  (* i := dstLen *)
  EmitHelperLocalGet(4);
  EmitHelperLocalSet(6);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* if i < idx then break *)
    EmitHelperLocalGet(6);
    EmitHelperLocalGet(2);
    EmitHelper(OpI32LtS);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* only copy if i + srcLen <= 255 *)
    EmitHelperLocalGet(6);
    EmitHelperLocalGet(3);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(255);
    EmitHelper(OpI32LeS);
    EmitHelper(OpIf); EmitHelper(WasmVoid);
      (* dst[i + srcLen] := dst[i] — 1-based byte positions *)
      EmitHelperLocalGet(1);
      EmitHelperLocalGet(6);
      EmitHelper(OpI32Add);
      EmitHelperLocalGet(3);
      EmitHelper(OpI32Add);
      EmitHelperLocalGet(1);
      EmitHelperLocalGet(6);
      EmitHelper(OpI32Add);
      EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
      EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpEnd);

    (* i := i - 1 *)
    EmitHelperLocalGet(6);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Sub);
    EmitHelperLocalSet(6);

    EmitHelper(OpBr); EmitHelperULEB128(0);
  EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* copy src[1..srcLen] into dst[idx..idx+srcLen-1] *)
  (* i := 0 *)
  EmitHelperI32Const(0);
  EmitHelperLocalSet(6);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);
    (* if i >= srcLen then break *)
    EmitHelperLocalGet(6);
    EmitHelperLocalGet(3);
    EmitHelper(OpI32GeS);
    EmitHelper(OpBrIf); EmitHelperULEB128(1);

    (* dst[idx + i] := src[i + 1] *)
    EmitHelperLocalGet(1);
    EmitHelperLocalGet(2);
    EmitHelper(OpI32Add);
    EmitHelperLocalGet(6);
    EmitHelper(OpI32Add);
    EmitHelperLocalGet(0);
    EmitHelperLocalGet(6);
    EmitHelper(OpI32Add);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load8u); EmitHelperULEB128(0); EmitHelperULEB128(0);
    EmitHelper(OpI32Store8); EmitHelperULEB128(0); EmitHelperULEB128(0);

    (* i := i + 1 *)
    EmitHelperLocalGet(6);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(6);

    EmitHelper(OpBr); EmitHelperULEB128(0);
  EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* dst[0] := newLen *)
  EmitHelperLocalGet(1);
  EmitHelperLocalGet(5);
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
  EmitHelperLocalSet(3);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);

    (* dst + counter*4 — store address *)
    EmitHelperLocalGet(0);
    EmitHelperLocalGet(3);
    EmitHelperI32Const(2);
    EmitHelper(OpI32Shl);
    EmitHelper(OpI32Add);

    (* a[counter]: load i32 at a + counter*4 *)
    EmitHelperLocalGet(1);
    EmitHelperLocalGet(3);
    EmitHelperI32Const(2);
    EmitHelper(OpI32Shl);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load); EmitHelperULEB128(2); EmitHelperULEB128(0);

    (* b[counter]: load i32 at b + counter*4 *)
    EmitHelperLocalGet(2);
    EmitHelperLocalGet(3);
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
    EmitHelperLocalGet(3);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(3);
    EmitHelperLocalGet(3);
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
  EmitHelperLocalSet(2);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);

    (* a[counter] *)
    EmitHelperLocalGet(0);
    EmitHelperLocalGet(2);
    EmitHelperI32Const(2);
    EmitHelper(OpI32Shl);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load); EmitHelperULEB128(2); EmitHelperULEB128(0);

    (* b[counter] *)
    EmitHelperLocalGet(1);
    EmitHelperLocalGet(2);
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
    EmitHelperLocalGet(2);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(2);
    EmitHelperLocalGet(2);
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
  EmitHelperLocalSet(2);

  EmitHelper(OpBlock); EmitHelper(WasmVoid);
  EmitHelper(OpLoop); EmitHelper(WasmVoid);

    (* a[counter] *)
    EmitHelperLocalGet(0);
    EmitHelperLocalGet(2);
    EmitHelperI32Const(2);
    EmitHelper(OpI32Shl);
    EmitHelper(OpI32Add);
    EmitHelper(OpI32Load); EmitHelperULEB128(2); EmitHelperULEB128(0);

    (* b[counter] — then NOT *)
    EmitHelperLocalGet(1);
    EmitHelperLocalGet(2);
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
    EmitHelperLocalGet(2);
    EmitHelperI32Const(1);
    EmitHelper(OpI32Add);
    EmitHelperLocalSet(2);
    EmitHelperLocalGet(2);
    EmitHelperI32Const(8);
    EmitHelper(OpI32LtU);
    EmitHelper(OpBrIf); EmitHelperULEB128(0);

  EmitHelper(OpEnd);
  EmitHelper(OpEnd);

  (* all words pass — a is subset of b *)
  EmitHelperI32Const(1);
end;

{** Append all bytes from a code buffer to the secCode section buffer. }
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
  slot 21 = __int_to_str, slot 22 = __write_char, slot 23 = __nil_check, slot 24 = __heap_alloc, slot 25 = __heap_free, slots 26+ = user funcs. }
var
  bodyLen: longint;
  i, j: longint;
begin
  CodeBufInit(secCode);

  { Function count }
  EmitULEB128(secCode, numDefinedFuncs);

  { Slot 0: _start body — conditional locals + (argsInit) + code + end.
    argsInitCode runs before user code so ParamCount/ParamStr see
    populated argv slots. }
  if startNlocals > 0 then begin
    bodyLen := 1 + 1 + 1 + argsInitCode.len + startCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);          { 1 local declaration block }
    CodeBufEmit(secCode, startNlocals); { N locals }
    CodeBufEmit(secCode, WasmI32);    { of type i32 }
  end else begin
    bodyLen := 1 + argsInitCode.len + startCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 0);  { 0 local declarations }
  end;
  CopyBufToCode(argsInitCode);
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

  { Slot 23: __nil_check body — always present (empty stub if unused) }
  if needsNilCheck then begin
    { __nil_check(addr) -> addr, traps if addr is zero }
    EmitULEB128(secCode, 11); { body size: 1 (locals) + 9 (code) + 1 (end) }
    CodeBufEmit(secCode, 0);  { 0 local declarations }
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { addr }
    CodeBufEmit(secCode, OpI32Eqz);
    CodeBufEmit(secCode, OpIf);
    CodeBufEmit(secCode, $40); { void block }
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
    CodeBufEmit(secCode, OpLocalGet); CodeBufEmit(secCode, 0); { return addr }
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 24: __heap_alloc body — always present (empty stub if unused) }
  if needsHeap then begin
    BuildHeapAllocHelper;
    { 4 extra locals beyond the one parameter }
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);       { 1 local declaration block }
    CodeBufEmit(secCode, 4);       { 4 locals: total, prev, cur, blk }
    CodeBufEmit(secCode, WasmI32);
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slot 25: __heap_free body — always present (empty stub if unused) }
  if needsHeap then begin
    BuildHeapFreeHelper;
    bodyLen := 1 + 1 + 1 + helperCode.len + 1;
    EmitULEB128(secCode, bodyLen);
    CodeBufEmit(secCode, 1);       { 1 local declaration block }
    CodeBufEmit(secCode, 1);       { 1 local: blk }
    CodeBufEmit(secCode, WasmI32);
    CopyBufToCode(helperCode);
    CodeBufEmit(secCode, OpEnd);
  end else begin
    EmitULEB128(secCode, 3);
    CodeBufEmit(secCode, 0);
    CodeBufEmit(secCode, OpUnreachable);
    CodeBufEmit(secCode, OpEnd);
  end;

  { Slots 26+: User-defined function bodies (skip imports) }
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

function ReadULEB128(var buf: TCodeBuf; var bufPos: longint): longint;
var
  b: byte;
  shift: longint;
  result_val: longint;
begin
  result_val := 0;
  shift := 0;
  repeat
    if bufPos >= buf.len then begin
      ReadULEB128 := result_val;
      exit;
    end;
    b := buf.data[bufPos];
    bufPos := bufPos + 1;
    result_val := result_val or ((longint(b) and $7F) shl shift);
    shift := shift + 7;
  until (b and $80) = 0;
  ReadULEB128 := result_val;
end;

{** Decode a signed LEB128 integer from a code buffer at pos.

  Advances pos past the encoded bytes. Used by the -d disassembler
  (DumpBytes) to display i32.const operands. }
function ReadSLEB128(var buf: TCodeBuf; var bufPos: longint): longint;
var
  b: byte;
  shift: longint;
  result_val: longint;
begin
  result_val := 0;
  shift := 0;
  repeat
    if bufPos >= buf.len then begin
      ReadSLEB128 := result_val;
      exit;
    end;
    b := buf.data[bufPos];
    bufPos := bufPos + 1;
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
  bufPos: longint;
  op: byte;
  indent: longint;
  i: longint;
  val: longint;
  align, ofs: longint;
  blockType: longint;
  labelCount: longint;
begin
  bufPos := startPos;
  indent := 2;
  while bufPos < endPos do begin
    op := buf.data[bufPos];
    bufPos := bufPos + 1;

    { Dedent for end/else before printing }
    if (op = OpEnd) or (op = OpElse) then
      if indent > 2 then indent := indent - 2;

    { Print indent }
    for i := 1 to indent do write(stderr, ' ');

    case op of
      OpUnreachable: writeln(stderr, 'unreachable');
      OpNop:         writeln(stderr, 'nop');
      OpBlock: begin
        blockType := ReadSLEB128(buf, bufPos);
        if blockType = -64 then { $40 = void block type }
          writeln(stderr, 'block')
        else
          writeln(stderr, 'block (result i32)');
        indent := indent + 2;
      end;
      OpLoop: begin
        blockType := ReadSLEB128(buf, bufPos);
        if blockType = -64 then { $40 = void block type }
          writeln(stderr, 'loop')
        else
          writeln(stderr, 'loop (result i32)');
        indent := indent + 2;
      end;
      OpIf: begin
        blockType := ReadSLEB128(buf, bufPos);
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
        val := ReadULEB128(buf, bufPos);
        writeln(stderr, 'br ', val);
      end;
      OpBrIf: begin
        val := ReadULEB128(buf, bufPos);
        writeln(stderr, 'br_if ', val);
      end;
      $0E: begin { br_table }
        labelCount := ReadULEB128(buf, bufPos);
        write(stderr, 'br_table');
        for i := 0 to labelCount do begin
          val := ReadULEB128(buf, bufPos);
          write(stderr, ' ', val);
        end;
        writeln(stderr);
      end;
      OpReturn:  writeln(stderr, 'return');
      OpCall: begin
        val := ReadULEB128(buf, bufPos);
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
        else if val = numImports + 23 then
          writeln(stderr, '  ;; __nil_check')
        else if val = numImports + 24 then
          writeln(stderr, '  ;; __heap_alloc')
        else if val = numImports + 25 then
          writeln(stderr, '  ;; __heap_free')
        else begin
          { User function }
          i := val - numImports - 26;
          if (i >= 0) and (i < numFuncs) then
            writeln(stderr, '  ;; ', funcs[i].name)
          else
            writeln(stderr);
        end;
      end;
      OpCallInd: begin
        val := ReadULEB128(buf, bufPos);
        writeln(stderr, 'call_indirect ', val);
        { table index }
        val := ReadULEB128(buf, bufPos);
      end;
      OpDrop:   writeln(stderr, 'drop');
      OpSelect: writeln(stderr, 'select');
      OpLocalGet: begin
        val := ReadULEB128(buf, bufPos);
        writeln(stderr, 'local.get ', val);
      end;
      OpLocalSet: begin
        val := ReadULEB128(buf, bufPos);
        writeln(stderr, 'local.set ', val);
      end;
      OpLocalTee: begin
        val := ReadULEB128(buf, bufPos);
        writeln(stderr, 'local.tee ', val);
      end;
      OpGlobalGet: begin
        val := ReadULEB128(buf, bufPos);
        write(stderr, 'global.get ', val);
        if val = 0 then
          writeln(stderr, '  ;; $sp')
        else if val <= 8 then
          writeln(stderr, '  ;; display[', val - 1, ']')
        else
          writeln(stderr);
      end;
      OpGlobalSet: begin
        val := ReadULEB128(buf, bufPos);
        write(stderr, 'global.set ', val);
        if val = 0 then
          writeln(stderr, '  ;; $sp')
        else if val <= 8 then
          writeln(stderr, '  ;; display[', val - 1, ']')
        else
          writeln(stderr);
      end;
      OpI32Load: begin
        align := ReadULEB128(buf, bufPos);
        ofs := ReadULEB128(buf, bufPos);
        writeln(stderr, 'i32.load align=', align, ' offset=', ofs);
      end;
      OpI32Load8s: begin
        align := ReadULEB128(buf, bufPos);
        ofs := ReadULEB128(buf, bufPos);
        writeln(stderr, 'i32.load8_s align=', align, ' offset=', ofs);
      end;
      OpI32Load8u: begin
        align := ReadULEB128(buf, bufPos);
        ofs := ReadULEB128(buf, bufPos);
        writeln(stderr, 'i32.load8_u align=', align, ' offset=', ofs);
      end;
      OpI32Load16s: begin
        align := ReadULEB128(buf, bufPos);
        ofs := ReadULEB128(buf, bufPos);
        writeln(stderr, 'i32.load16_s align=', align, ' offset=', ofs);
      end;
      OpI32Load16u: begin
        align := ReadULEB128(buf, bufPos);
        ofs := ReadULEB128(buf, bufPos);
        writeln(stderr, 'i32.load16_u align=', align, ' offset=', ofs);
      end;
      OpI32Store: begin
        align := ReadULEB128(buf, bufPos);
        ofs := ReadULEB128(buf, bufPos);
        writeln(stderr, 'i32.store align=', align, ' offset=', ofs);
      end;
      OpI32Store8: begin
        align := ReadULEB128(buf, bufPos);
        ofs := ReadULEB128(buf, bufPos);
        writeln(stderr, 'i32.store8 align=', align, ' offset=', ofs);
      end;
      OpI32Store16: begin
        align := ReadULEB128(buf, bufPos);
        ofs := ReadULEB128(buf, bufPos);
        writeln(stderr, 'i32.store16 align=', align, ' offset=', ofs);
      end;
      OpI32Const: begin
        val := ReadSLEB128(buf, bufPos);
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
        if bufPos < endPos then begin
          val := ReadULEB128(buf, bufPos);
          case val of
            $0A: begin { memory.copy }
              { skip two memory indices (0, 0) }
              ReadULEB128(buf, bufPos);
              ReadULEB128(buf, bufPos);
              writeln(stderr, 'memory.copy');
            end;
            $0B: begin { memory.fill }
              ReadULEB128(buf, bufPos); { memory index }
              writeln(stderr, 'memory.fill');
            end;
          else
            writeln(stderr, '0xFC ', val);
          end;
        end else
          writeln(stderr, '0xFC (truncated)');
      end;
    else begin
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
  for i := 1 to 25 do begin
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
      23: if needsNilCheck then slotName := '__nil_check' else continue;
      24: if needsHeap then slotName := '__heap_alloc' else continue;
      25: if needsHeap then slotName := '__heap_free' else continue;
    end;
    writeln(stderr, 'func[', numImports + i, '] ', slotName, '  (helper, code in code section)');
  end;
  writeln(stderr);

  { User-defined functions }
  for i := 0 to numFuncs - 1 do begin
    if funcs[i].bodyStart = -2 then begin
      writeln(stderr, 'func[', numImports + 26 + i, '] ', funcs[i].name,
              '  (import)');
      continue;
    end;
    writeln(stderr, 'func[', numImports + 26 + i, '] ', funcs[i].name,
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
  TypeI32I32;    { always needed for __nil_check stub }

  { Assemble all sections }
  AssembleTypeSection;
  ProgressStage(2, 'Types');
  AssembleImportSection;
  ProgressStage(3, 'Imports');
  AssembleFunctionSection;
  ProgressStage(4, 'Functions');
  AssembleMemorySection;
  ProgressStage(5, 'Memory');
  AssembleGlobalSection;
  ProgressStage(6, 'Globals');
  AssembleExportSection;
  ProgressStage(7, 'Exports');
  AssembleCodeSectionFixed;
  ProgressStage(8, 'Code');

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
  ProgressStage(9, 'Data');

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
  { An empty file name binds to standard output. Do not reach for
    '/dev/stdout': that path is Linux-specific, fails on macOS with a file
    access error, and does not exist on Windows at all. Rewrite with a record
    size of 1 gives an untyped binary stream, which also avoids the CRLF
    translation a text file would apply on Windows. }
  Assign(outFile, '');
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

{** Reset all global compiler state so Compile can be called cleanly.

  Clears the symbol table, scopes, buffers, imports, exports, function
  table, and all accumulated WASM section buffers. Called once at the
  start of each compilation. }
procedure Init;
var
  i: longint;
  defArg: string;
  argCount: longint;
  skipArg: boolean;
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
  CodeBufInit(argsInitCode);

  srcLine := 1;
  srcCol := 0;
  atEof := false;
  hasPushback := false;
  pendingTok := false;

  numWasmTypes := 0;
  numTypes := 0;
  numPendingPtr := 0;
  optFileIO := false;
  emittedAnyCode := false;
  idxPathOpen := -1;
  idxFdClose := -1;
  stmtUsedResultBuf := false;
  stmtArenaBytes := 0;
  numFields := 0;
  numStructCopies := 0;
  numVarInits := 0;
  numImports := 0;
  numDefinedFuncs := 26; { slots 0-25: _start, __write_int, __read_int, __str_assign, __write_str, __str_compare, __read_str, __str_append, __str_copy, __str_pos, __str_delete, __str_insert, __range_check, __checked_add, __checked_sub, __checked_mul, __set_union, __set_intersect, __set_diff, __set_eq, __set_subset, __int_to_str, __write_char, __nil_check, __heap_alloc, __heap_free }
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
  addrArgc := -1;
  addrArgBufSize := -1;
  addrArgv := -1;
  addrArgBuf := -1;
  addrArgSlots := -1;
  needsArgs := false;

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
  needsNilCheck := false;
  needsHeap := false;
  addrHeapFree := -1;
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
  concatScratchBase := 0;
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
  optAlign := 4;
  optDump := false;
  optStackChecks := true;
  optProgress := false;
  optVerbose := false;
  optDebug := false;
  optProgressTotal := 0;
  progressStep := 1;
  progressNextLine := 1;
  skipArg := false;
  optLevel := 1;
  numDefined := 0;
  DefineSymbol('CPAS');

  { Parse command-line arguments. Under fpc bootstrap this uses the
    RTL ParamCount/ParamStr; under self-hosted cpas these are intrinsics
    backed by WASI args_sizes_get/args_get. }
  for i := 1 to ParamCount do begin
    if skipArg then
      skipArg := false
    else if ParamStr(i) = '-dump' then
      optDump := true
    else if ParamStr(i) = '-v' then
      optVerbose := true
    else if ParamStr(i) = '-debug' then
      optDebug := true
    else if ParamStr(i) = '-progress' then begin
      optProgress := true;
      { An all-digits argument after -progress is the source line count,
        which selects line-based reporting. Anything else is left for the
        next iteration to handle as its own option. }
      if i < ParamCount then begin
        argCount := ArgToInt(ParamStr(i + 1));
        if argCount > 0 then begin
          optProgressTotal := argCount;
          progressStep := optProgressTotal div ProgressReports;
          if progressStep < 1 then
            progressStep := 1;
          progressNextLine := progressStep;
          skipArg := true;
        end;
      end;
    end
    { Initial state for the range and stack check switches. A directive in
      the source still overrides from the point it appears; these only set
      what the file starts with, so the suite can be run under either
      configuration without editing every test. }
    else if ParamStr(i) = '-R+' then
      optRangeChecks := true
    else if ParamStr(i) = '-R-' then
      optRangeChecks := false
    else if ParamStr(i) = '-S+' then
      optStackChecks := true
    else if ParamStr(i) = '-S-' then
      optStackChecks := false
    else if ParamStr(i) = '-O0' then
      optLevel := 0
    else if ParamStr(i) = '-O1' then
      optLevel := 1
    else if (length(ParamStr(i)) > 2) and (copy(ParamStr(i), 1, 2) = '-d') then begin
      defArg := copy(ParamStr(i), 3, 255);
      UpcaseStr(defArg);
      DefineSymbol(defArg);
    end
    else begin
      WriteErrorLn('Error: unknown option: ' + ParamStr(i));
      halt(1);
    end;
  end;

  { Pre-register all WASI imports so numImports is stable before
    any code emission. WASI hosts always provide these functions. }
  idxFdWrite := AddImport('wasi_snapshot_preview1', 'fd_write', TypeI32x4I32);
  idxFdRead := AddImport('wasi_snapshot_preview1', 'fd_read', TypeI32x4I32);
  idxProcExit := AddImport('wasi_snapshot_preview1', 'proc_exit', TypeI32Void);
  idxArgsSizesGet := AddImport('wasi_snapshot_preview1', 'args_sizes_get', TypeI32x2I32);
  idxArgsGet := AddImport('wasi_snapshot_preview1', 'args_get', TypeI32x2I32);



  InitSymTable;
  AddBuiltins;
end;

begin
  Init;

  ProgressStage(0, 'Parsing');
  if optProgress and (optProgressTotal > 0) then
    ProgressReport(0, optProgressTotal, 'Parsing');

  { Read first character }
  ReadCh;

  { Skip a UTF-8 byte order mark (EF BB BF) if the file starts with one.
    A BOM is valid UTF-8 and Windows editors write one by default, so
    rejecting it turns an ordinary save into "unexpected character" on
    line 1 with nothing to act on. Only a leading BOM is skipped; one
    appearing later is still an error. }
  if (not atEof) and (ch = #$EF) then begin
    ReadCh;
    if (not atEof) and (ch = #$BB) then begin
      ReadCh;
      if (not atEof) and (ch = #$BF) then begin
        ReadCh;
        srcCol := 0;
      end else
        Error('unexpected character in byte order mark');
    end else
      Error('unexpected character in byte order mark');
  end;

  { Skip shebang line (e.g., #!/usr/bin/env cpas) }
  if (not atEof) and (ch = '#') then
    while (not atEof) and (ch <> #10) do
      ReadCh;

  { Read first token }
  NextToken;

  { Parse: program Ident ; Block . }
  { Register the filesystem imports before the header is consumed, which is
    after every global directive has been seen and before any code is
    emitted. Helper slots are numbered from the import count and those
    numbers become immediates in call instructions, so the count has to be
    settled here or not at all. }
  if optFileIO then begin
    idxPathOpen := AddImport('wasi_snapshot_preview1', 'path_open',
                             TypePathOpen);
    idxFdClose := AddImport('wasi_snapshot_preview1', 'fd_close',
                            TypeI32I32);
  end;
  emittedAnyCode := true;

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

  ProgressStage(1, 'Parsed');
  if optProgress and (optProgressTotal > 0) then
    ProgressReport(srcLine, optProgressTotal, 'Parsed');

  { Set _start locals based on whether string/case temps were needed }
  if curFuncNeedsCaseTemp then
    startNlocals := startNlocals + 2  { string temp + case temp }
  else if curFuncNeedsStringTemp then
    startNlocals := startNlocals + 1;

  { Args init prelude needs 4 i32 scratch locals (argc, i, cstr, len).
    Indices 0..3 are reused — string/case temps overlap, but they are
    written before being read by user code so the overlap is harmless. }
  if needsArgs and (startNlocals < 4) then
    startNlocals := 4;

  { Assemble and write WASM module }
  WriteModule;

  { Final progress line. In line mode the count is forced to the total so
    a host sees the ratio reach 1 even if it passed a high line count. }
  if optProgress then begin
    if optProgressTotal > 0 then
      ProgressReport(optProgressTotal, optProgressTotal, 'Done')
    else
      ProgressReport(ProgressStages, ProgressStages, 'Done');
  end;

  { Summary for -v }
  if optVerbose then begin
    str(srcLine, infoNum);
    Info(infoNum + ' source lines');
    str(numImports, infoNum);
    Info(infoNum + ' imports');
    str(numFuncs, infoNum);
    Info(infoNum + ' user functions');
    str(outBuf.len, infoNum);
    Info(infoNum + ' bytes written');
  end;

  { Dump instructions if -dump flag was given }
  if optDump then
    DumpModule;
end.
