{$MODE TP}
program cpas;
{** Compact Pascal compiler — targets WASM 1.0 binary format.
  Reads Pascal source from stdin, writes WASM binary to stdout,
  writes error diagnostics to stderr.

  Bootstrapped with fpc -Mtp. The compiler source uses longint
  (32-bit) everywhere to avoid TP's 16-bit integer.
}

{ ---- Constants ---- }

const
  Version = '0.1';

  { Section buffer sizes }
  SmallBufMax = 4095;    { 4 KB for small sections }
  CodeBufMax  = 131071;  { 128 KB for code section }
  DataBufMax  = 65535;   { 64 KB for data section }

  { Symbol table limits }
  MaxSyms    = 1024;
  MaxScopes  = 32;
  MaxFuncs   = 256;   { max user-defined functions }

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

  { Type kinds }
  tyNone      = 0;
  tyInteger   = 1;
  tyBoolean   = 2;
  tyChar      = 3;
  tyString    = 4;

  { Symbol kinds }
  skNone      = 0;
  skConst     = 1;
  skVar       = 2;
  skType      = 3;
  skProc      = 4;
  skFunc      = 5;

  { Operator precedences for Pratt parser }
  PrecNone    = 0;
  PrecOr      = 1;  { or, or else }
  PrecAnd     = 2;  { and, and then }
  PrecCompare = 3;  { = <> < > <= >= in }
  PrecAdd     = 4;  { + - }
  PrecMul     = 5;  { * div mod }
  PrecUnary   = 6;  { not, unary +/- }

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
    level: longint;  { nesting level }
    offset: longint; { stack offset for vars, value for consts, func index for procs }
    size: longint;   { byte size of var }
    isVarParam: boolean;   { true if this is a var parameter (passed by reference) }
    isConstParam: boolean; { true if this is a const parameter (read-only) }
  end;

  { WASM type signature }
  TWasmType = record
    nparams: longint;
    params: array[0..15] of byte;  { WASM value types }
    nresults: longint;
    results: array[0..3] of byte;
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

  { Defined function record — tracks each compiled function body }
  TFuncEntry = record
    name: string[63];     { function name for WASM name section }
    typeidx: longint;     { index into wasmTypes }
    bodyStart: longint;   { offset into funcBodies buffer }
    bodyLen: longint;     { length of body bytes in funcBodies }
    nlocals: longint;     { number of extra locals (beyond params) }
    nparams: longint;     { number of WASM parameters }
    varParams: array[0..15] of boolean; { which params are var (by-reference) }
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

  { Start function code - accumulated separately, then wrapped }
  startCode: TCodeBuf;

  { Helper function code buffer (for __write_int etc.) }
  helperCode: TCodeBuf;

  { Has the program used I/O? }
  needsFdWrite: boolean;
  needsFdRead: boolean;
  needsProcExit: boolean;
  needsWriteInt: boolean;

  { Pending compiler directives }
  hasPendingImport: boolean;
  pendingImportMod: string[63];
  pendingImportName: string[63];
  hasPendingExport: boolean;
  pendingExportName: string[63];

  (* User-defined exports from EXPORT directives *)
  userExports: array[0..31] of TExportEntry;
  numUserExports: longint;

  { Output file for binary WASM }
  outFile: file;

  { Temp buffer for LEB128 etc }
  tmpBuf: array[0..15] of byte;

{ ---- Forward declarations ---- }

procedure ParseBlock; forward;
procedure ParseStatement; forward;
procedure ParseExpression(minPrec: longint); forward;
procedure ParseProcDecl; forward;

{ ---- Error handling ---- }

procedure Error(msg: string);
begin
  writeln(stderr, 'Error: [', srcLine, ':', srcCol, '] ', msg);
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

{ ---- Scanner ---- }

function UpCase(c: char): char;
begin
  if (c >= 'a') and (c <= 'z') then
    UpCase := chr(ord(c) - 32)
  else
    UpCase := c;
end;

procedure SkipWhitespace;
begin
  while (not atEof) and (ch <= ' ') do
    ReadCh;
end;

procedure SkipLineComment;
begin
  { // comment - skip to end of line }
  while (not atEof) and (ch <> #10) do
    ReadCh;
end;

procedure SkipBraceComment;
(* Parse brace comment or compiler directive (IMPORT, EXPORT).
   On entry, ch = opening brace. On exit, ch = character after closing brace. *)
var
  directive: string;
  modName: string[63];
  impName: string[63];
  expName: string[63];
  i: longint;
begin
  ReadCh; { skip opening brace }
  if ch = '$' then begin
    { Potential compiler directive }
    ReadCh; { skip $ }
    directive := '';
    while (not atEof) and (ch <> '}') and (ch > ' ') do begin
      if ch in ['a'..'z'] then
        directive := directive + chr(ord(ch) - 32)
      else
        directive := directive + ch;
      ReadCh;
    end;
    if directive = 'IMPORT' then begin
      (* IMPORT 'module' name *)
      while (not atEof) and (ch <= ' ') and (ch <> '}') do
        ReadCh;
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
      while (not atEof) and (ch <= ' ') and (ch <> '}') do
        ReadCh;
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
      while (not atEof) and (ch <= ' ') and (ch <> '}') do
        ReadCh;
      expName := '';
      while (not atEof) and (ch <> '}') and (ch > ' ') do begin
        expName := expName + ch;
        ReadCh;
      end;
      if length(expName) = 0 then
        Error('{$EXPORT} expects export name');
      hasPendingExport := true;
      pendingExportName := expName;
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
  else if s = 'EXIT' then LookupKeyword := tkExit;
end;

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
      { it was just a dot after a number, e.g. "1.." for range }
      { push back by setting tokKind specially }
      tokKind := tkInteger;
      tokInt := n;
      { we consumed the dot - need to handle this }
      { actually we peeked one char too far, handle dotdot }
      if ch = '.' then begin
        { it was N.. (range) - we'll handle this in NextToken }
        { for now, back up: we have n and a pending '..' }
        { store the dot-dot state - simplify: set a flag }
      end;
      { This gets complex. Let's simplify: don't peek past the number. }
      { Real detection: if we see N. and next char is a digit, error. }
      { Otherwise, the dot is a separate token. But we already read it. }
      { Undo: not possible with single-char lookahead on stdin. }
      { Solution: buffer the pending token. }
    end;
  end;
  tokKind := tkInteger;
  tokInt := n;
end;

{ Pending token mechanism for when scanner reads too far }
var
  pendingTok: boolean;
  pendingKind: longint;
  pendingInt: longint;
  pendingStr: string;

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
              tokKind := tkAnd  { we'll handle 'and then' semantics in parser }
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
              tokKind := tkOr  { we'll handle 'or else' semantics in parser }
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

function AddWasmType(np: longint; p: array of byte;
                     nr: longint; r: array of byte): longint;
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
var dummy: array[0..0] of byte;
begin
  dummy[0] := 0;
  TypeVoidVoid := AddWasmType(0, dummy, 0, dummy);
end;

function TypeI32Void: longint;
var p, r: array[0..0] of byte;
begin
  p[0] := WasmI32;
  r[0] := 0;
  TypeI32Void := AddWasmType(1, p, 0, r);
end;

function TypeI32x4I32: longint;
var p: array[0..3] of byte;
    r: array[0..0] of byte;
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

{ Emit i32.load from [addr] }
procedure EmitI32Load(align, offset: longint);
begin
  CodeBufEmit(startCode, OpI32Load);
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
  syms[numSyms].level := curNestLevel;
  syms[numSyms].offset := 0;
  syms[numSyms].size := 0;
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

{ ---- Write/Writeln code generation ---- }

procedure EmitWriteString(addr, len: longint);
{** Emit WASM code to write a string literal via fd_write.
  ;; WAT: i32.const <iovec_addr>    ;; iovec base
  ;;      i32.const <str_addr>      ;; buf ptr
  ;;      i32.store                 ;; iovec.buf = str_addr
  ;;      i32.const <iovec_addr+4>  ;; iovec len field
  ;;      i32.const <str_len>       ;; length
  ;;      i32.store                 ;; iovec.len = str_len
  ;;      i32.const 1               ;; fd = stdout
  ;;      i32.const <iovec_addr>    ;; iovs ptr
  ;;      i32.const 1               ;; iovs_len = 1
  ;;      i32.const <nwritten_addr> ;; nwritten ptr
  ;;      call $fd_write
  ;;      drop                      ;; discard errno
}
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

  { Call fd_write(1, iovec, 1, nwritten) }
  EmitI32Const(1);              { fd = stdout }
  EmitI32Const(addrIovec);      { iovs }
  EmitI32Const(1);              { iovs_len }
  EmitI32Const(addrNwritten);   { nwritten }
  EmitCall(fdw);
  EmitOp(OpDrop);               { discard errno }
end;

procedure EmitWriteNewline;
begin
  EnsureIOBuffers;
  EmitWriteString(addrNewline, 1);
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

function EnsureWriteInt: longint;
{** Ensure the __write_int helper function is registered.
  Returns its WASM function index.
  __write_int is pre-allocated at slot 1 (right after _start)
  so its index is stable: numImports + 1. User-defined functions
  go into slots 2+. }
begin
  if not needsWriteInt then begin
    EnsureIntToStr;
    EnsureIOBuffers;
    needsWriteInt := true;
  end;
  EnsureWriteInt := numImports + 1; { slot 1 = __write_int }
end;

procedure EmitWriteInt;
{** Emit a call to the __write_int helper function.
  The integer value is already on the WASM operand stack. }
begin
  EmitCall(EnsureWriteInt);
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
begin
  { Prefix }
  case tokKind of
    tkInteger: begin
      EmitI32Const(tokInt);
      NextToken;
    end;

    tkString: begin
      { String literal in expression context - for write() args }
      { Store the address and length as a marker }
      Error('string expression not supported in this context');
    end;

    tkTrue: begin
      EmitI32Const(1);
      NextToken;
    end;

    tkFalse: begin
      EmitI32Const(0);
      NextToken;
    end;

    tkIdent: begin
      sym := LookupSym(tokStr);
      if sym < 0 then
        Error('undeclared identifier: ' + tokStr);
      case syms[sym].kind of
        skConst: begin
          EmitI32Const(syms[sym].offset);
          NextToken;
        end;
        skVar: begin
          if syms[sym].offset < 0 then begin
            { WASM local (parameter or function return value) }
            EmitOp(OpLocalGet);
            EmitULEB128(startCode, -(syms[sym].offset + 1));
            if syms[sym].isVarParam then begin
              { ;; WAT: i32.load  — dereference var param pointer }
              EmitI32Load(2, 0);
            end;
          end else begin
            { Load variable from stack frame (local or upvalue) }
            EmitFramePtr(syms[sym].level);
            EmitI32Const(syms[sym].offset);
            EmitOp(OpI32Add);
            EmitI32Load(2, 0);
          end;
          NextToken;
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
                if tokKind <> tkIdent then
                  Error('variable expected for var parameter');
                argSym := LookupSym(tokStr);
                if argSym < 0 then
                  Error('undeclared identifier: ' + tokStr);
                if syms[argSym].kind <> skVar then
                  Error('variable expected for var parameter');
                if syms[argSym].isVarParam then begin
                  { Already a pointer — pass it through }
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
              end else
                ParseExpression(PrecNone);
              argIdx := argIdx + 1;
              if tokKind = tkComma then
                NextToken;
            end;
            Expect(tkRParen);
          end;
          EmitCall(syms[sym].offset);
          { Return value is left on WASM stack }
        end;
      else
        Error('cannot use ' + tokStr + ' in expression');
      end;
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

    tkNot: begin
      NextToken;
      ParseExpression(PrecUnary);
      { not = xor with -1 (all bits) }
      EmitI32Const(-1);
      EmitOp(OpI32Xor);
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
      tkOr:        prec := PrecOr;
      tkStar:      prec := PrecMul;
      tkDiv:       prec := PrecMul;
      tkMod:       prec := PrecMul;
      tkAnd:       prec := PrecAnd;
      tkEqual:     prec := PrecCompare;
      tkNotEqual:  prec := PrecCompare;
      tkLess:      prec := PrecCompare;
      tkGreater:   prec := PrecCompare;
      tkLessEq:    prec := PrecCompare;
      tkGreaterEq: prec := PrecCompare;
    else
      break; { not an operator }
    end;

    if prec <= minPrec then
      break;

    NextToken;
    ParseExpression(prec);

    { Emit operator }
    case op of
      tkPlus:      EmitOp(OpI32Add);
      tkMinus:     EmitOp(OpI32Sub);
      tkStar:      EmitOp(OpI32Mul);
      tkDiv:       EmitOp(OpI32DivS);
      tkMod:       EmitOp(OpI32RemS);
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
end;

procedure ParseWriteArgs(withNewline: boolean);
{** Parse arguments to write/writeln and emit fd_write calls. }
var
  addr, slen: longint;
begin
  if tokKind = tkLParen then begin
    NextToken;
    while tokKind <> tkRParen do begin
      if tokKind = tkString then begin
        { String literal - emit directly }
        slen := length(tokStr);
        addr := EmitDataString(tokStr);
        EmitWriteString(addr, slen);
        NextToken;
      end else begin
        { Integer expression }
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

procedure ParseVarDecl;
{** Parse variable declarations in a var section. }
var
  names: array[0..31] of string[63];
  nnames: longint;
  i, sym: longint;
  typeName: string;
  typId: longint;
  varSize: longint;
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
    if tokKind = tkIdent then begin
      typeName := tokStr;
      typId := LookupSym(typeName);
      if typId < 0 then
        Error('unknown type: ' + typeName);
      if syms[typId].kind <> skType then
        Error(typeName + ' is not a type');
      NextToken;
    end else if tokKind = tkString_kw then begin
      { string type }
      typId := -1; { TODO: proper string type }
      NextToken;
    end else
      Error('type name expected');

    { Determine size }
    if typId >= 0 then begin
      case syms[typId].typ of
        tyInteger: varSize := 4;
        tyBoolean: varSize := 4;
        tyChar:    varSize := 4;  { stored as i32 }
      else
        varSize := 4;
      end;
    end else
      varSize := 4;

    { Add symbols and allocate stack space }
    for i := 0 to nnames - 1 do begin
      sym := AddSym(names[i], skVar, syms[typId].typ);
      syms[sym].offset := curFrameSize;
      syms[sym].size := varSize;
      curFrameSize := curFrameSize + varSize;
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
begin
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
      sym := LookupSym(name);
      if sym < 0 then
        Error('undeclared identifier: ' + name);
      NextToken;
      if (syms[sym].kind = skVar) and (tokKind = tkAssign) then begin
        { Assignment: var := expr }
        if syms[sym].isConstParam then
          Error('cannot assign to const parameter ''' + name + '''');
        NextToken;
        if syms[sym].isVarParam then begin
          { ;; WAT: local.get <param>  — get pointer }
          { ;;      <expr>              — value to store }
          { ;;      i32.store           — store through pointer }
          EmitOp(OpLocalGet);
          EmitULEB128(startCode, -(syms[sym].offset + 1));
          ParseExpression(PrecNone);
          EmitI32Store(2, 0);
        end
        else if syms[sym].offset < 0 then begin
          { WASM local (value parameter or function return value) }
          ParseExpression(PrecNone);
          EmitOp(OpLocalSet);
          EmitULEB128(startCode, -(syms[sym].offset + 1));
        end else begin
          { Stack frame variable (local or upvalue) }
          EmitFramePtr(syms[sym].level);
          EmitI32Const(syms[sym].offset);
          EmitOp(OpI32Add);
          ParseExpression(PrecNone);
          EmitI32Store(2, 0);
        end;
      end
      else if (syms[sym].kind = skFunc) and (tokKind = tkAssign) then begin
        { Function return value assignment: FuncName := expr }
        NextToken;
        ParseExpression(PrecNone);
        { Store in the hidden WASM local at index nparams }
        EmitOp(OpLocalSet);
        EmitULEB128(startCode, funcs[syms[sym].size].nparams);
      end
      else if (syms[sym].kind = skProc) or (syms[sym].kind = skFunc) then begin
        { Procedure/function call (discard result for functions) }
        if tokKind = tkLParen then begin
          NextToken;
          argIdx := 0;
          while tokKind <> tkRParen do begin
            if funcs[syms[sym].size].varParams[argIdx] then begin
              { var param: pass address of the variable }
              if tokKind <> tkIdent then
                Error('variable expected for var parameter');
              argSym := LookupSym(tokStr);
              if argSym < 0 then
                Error('undeclared identifier: ' + tokStr);
              if syms[argSym].kind <> skVar then
                Error('variable expected for var parameter');
              if syms[argSym].isVarParam then begin
                { Already a pointer — pass it through }
                EmitOp(OpLocalGet);
                EmitULEB128(startCode, -(syms[argSym].offset + 1));
              end
              else if syms[argSym].offset < 0 then
                { Can't take address of a value parameter }
                Error('cannot pass value parameter by reference')
              else begin
                { Address = frame[level] + offset }
                EmitFramePtr(syms[argSym].level);
                EmitI32Const(syms[argSym].offset);
                EmitOp(OpI32Add);
              end;
              NextToken;
            end else
              ParseExpression(PrecNone);
            argIdx := argIdx + 1;
            if tokKind = tkComma then
              NextToken;
          end;
          Expect(tkRParen);
        end;
        EmitCall(syms[sym].offset);
        if syms[sym].kind = skFunc then
          EmitOp(OpDrop); { discard return value }
      end else
        Error('assignment or procedure call expected after ' + name);
    end;

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

    tkIf: begin
      NextToken;
      ParseExpression(PrecNone);
      Expect(tkThen);
      { ;; WAT: if (result void) }
      EmitOp(OpIf);
      EmitOp(WasmVoid);  { void block type }
      ParseStatement;
      if tokKind = tkElse then begin
        NextToken;
        EmitOp(OpElse);
        ParseStatement;
      end;
      EmitOp(OpEnd);
    end;

    tkWhile: begin
      NextToken;
      { ;; WAT: block $exit
        ;;        loop $loop }
      EmitOp(OpBlock);
      EmitOp(WasmVoid);
      EmitOp(OpLoop);
      EmitOp(WasmVoid);
      { Evaluate condition }
      ParseExpression(PrecNone);
      Expect(tkDo);
      { ;; WAT: i32.eqz
        ;;      br_if 1  ;; break to $exit }
      EmitOp(OpI32Eqz);
      EmitOp(OpBrIf);
      EmitULEB128(startCode, 1);
      { Body }
      ParseStatement;
      { ;; WAT: br 0  ;; continue to $loop
        ;;      end    ;; loop
        ;;      end    ;; block }
      EmitOp(OpBr);
      EmitULEB128(startCode, 0);
      EmitOp(OpEnd);  { end loop }
      EmitOp(OpEnd);  { end block }
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
        { Parse limit - we need to store it somewhere. Use data segment scratch. }
        { For simplicity, use a data segment location }
        { Actually, the limit is evaluated once. We'll use the stack frame. }
        { For now: emit limit to a scratch location in data segment }
        { TODO: proper local variable for limit }

        { Simple approach: evaluate limit, store to intbuf temp area }
        EnsureIntToStr; { ensures addrIntBuf is allocated }
        EmitI32Const(addrIntBuf);
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
        EmitI32Const(addrIntBuf);
        EmitI32Load(2, 0);
        EmitOp(OpI32GtS);
        EmitOp(OpBrIf);
        EmitULEB128(startCode, 1);

        { Body }
        ParseStatement;

        { Increment counter }
        EmitFramePtr(syms[sym].level);
        EmitI32Const(syms[sym].offset);
        EmitOp(OpI32Add);
        { Load current value }
        EmitFramePtr(syms[sym].level);
        EmitI32Const(syms[sym].offset);
        EmitOp(OpI32Add);
        EmitI32Load(2, 0);
        EmitI32Const(1);
        EmitOp(OpI32Add);
        EmitI32Store(2, 0);

        { Loop back }
        EmitOp(OpBr);
        EmitULEB128(startCode, 0);
        EmitOp(OpEnd);
        EmitOp(OpEnd);
      end else begin
        { downto }
        NextToken;
        EnsureIntToStr;
        EmitI32Const(addrIntBuf);
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
        EmitI32Const(addrIntBuf);
        EmitI32Load(2, 0);
        EmitOp(OpI32LtS);
        EmitOp(OpBrIf);
        EmitULEB128(startCode, 1);

        ParseStatement;

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
      { ;; WAT: loop $loop }
      EmitOp(OpLoop);
      EmitOp(WasmVoid);
      { Parse statements }
      ParseStatement;
      while tokKind = tkSemicolon do begin
        NextToken;
        if tokKind <> tkUntil then
          ParseStatement;
      end;
      Expect(tkUntil);
      ParseExpression(PrecNone);
      { ;; WAT: i32.eqz
        ;;      br_if 0  ;; if false, continue loop }
      EmitOp(OpI32Eqz);
      EmitOp(OpBrIf);
      EmitULEB128(startCode, 0);
      EmitOp(OpEnd);
    end;

    tkExit: begin
      NextToken;
      { ;; WAT: return }
      EmitOp(OpReturn);
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
  savedStartCode: TCodeBuf;
  bodyStart: longint;
  funcIdx: longint;
  retTyp: longint;
  retTypSym: longint;
  nlocals: longint;
  nparams: longint;
  typIdx: longint;
  paramNames: array[0..15] of string[63];
  paramTypes: array[0..15] of longint;
  paramIsVar: array[0..15] of boolean;
  paramIsConst: array[0..15] of boolean;
  np: longint;
  i: longint;
  groupStart, groupEnd: longint;
  isVarParam: boolean;
  isConstParam: boolean;
  pTypeName: string;
  pTypSym: longint;
  wasmParams: array[0..15] of byte;
  wasmResults: array[0..0] of byte;
  nWasmResults: longint;
  savedNestLevel: longint;
  savedDisplayLocal: longint;
  myDisplayLocal: longint;
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
      for i := groupStart to groupEnd - 1 do
        paramTypes[i] := syms[pTypSym].typ;

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
      funcs[numFuncs].varParams[i] := false; { imports have no var params }

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
    for i := 0 to np - 1 do
      funcs[numFuncs].varParams[i] := paramIsVar[i];

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
  savedStartCode := startCode;
  CodeBufInit(startCode);
  savedFrameSize := curFrameSize;
  curFrameSize := 0;

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

  { Enter scope for procedure body }
  EnterScope;

  { Add parameters as locals (WASM params are local 0..np-1) }
  nparams := np;
  for i := 0 to np - 1 do begin
    sym := AddSym(paramNames[i], skVar, paramTypes[i]);
    { Parameters are WASM locals, not stack frame vars.
      Use negative offset as a flag: -(local_index + 1) }
    syms[sym].offset := -(i + 1);
    syms[sym].size := 4;
    syms[sym].isVarParam := paramIsVar[i];
    syms[sym].isConstParam := paramIsConst[i];
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

  { Parse the block (declarations + begin...end) }
  ParseBlock;

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
    - saved display value: 1 local (always present for all procs) }
  nlocals := 1; { saved display }
  if isFunc then
    nlocals := 2; { return value + saved display }

  { Copy compiled body to funcBodies }
  bodyStart := funcBodies.len;
  for i := 0 to startCode.len - 1 do
    CodeBufEmit(funcBodies, startCode.data[i]);

  { Update func entry }
  funcs[funcIdx].bodyStart := bodyStart;
  funcs[funcIdx].bodyLen := startCode.len;
  funcs[funcIdx].nlocals := nlocals;
  funcs[funcIdx].nparams := nparams;
  for i := 0 to np - 1 do
    funcs[funcIdx].varParams[i] := paramIsVar[i];

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
  startCode := savedStartCode;
  curFrameSize := savedFrameSize;
end;

procedure ParseBlock;
var
  savedFrameSize: longint;
begin
  savedFrameSize := curFrameSize;

  { Declarations }
  while (tokKind = tkConst) or (tokKind = tkVar) or (tokKind = tkType)
        or (tokKind = tkProcedure) or (tokKind = tkFunction) do begin
    case tokKind of
      tkConst: begin
        NextToken;
        Error('const declarations not yet implemented');
      end;
      tkVar: begin
        NextToken;
        ParseVarDecl;
      end;
      tkType: begin
        NextToken;
        Error('type declarations not yet implemented');
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

  { Statement part }
  if tokKind = tkBegin then
    ParseStatement
  else
    Expected('"begin"');

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

procedure WriteOutputBytes(var buf; count: longint);
var
  p: ^byte;
  i: longint;
begin
  p := @buf;
  for i := 0 to count - 1 do begin
    WriteOutputByte(p^);
    p := pointer(ptrint(p) + 1);
  end;
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

procedure WriteSection(id: byte; var buf; bufLen: longint);
begin
  if bufLen = 0 then exit;
  WriteOutputByte(id);
  WriteOutputULEB128(bufLen);
  WriteOutputBytes(buf, bufLen);
end;

procedure AssembleTypeSection;
{** Build the type section from the wasmTypes table. }
var
  i, j: longint;
begin
  SmallBufInit(secType);
  SmallBufEmit(secType, numWasmTypes); { type count }
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
  SmallBufEmit(secImport, numImports);
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
  SmallBufEmit(secFunc, numDefinedFuncs);
  { Slot 0: _start uses type void -> void }
  SmallEmitULEB128(secFunc, TypeVoidVoid);
  { Slot 1: __write_int uses type i32 -> void (always present) }
  SmallEmitULEB128(secFunc, TypeI32Void);
  { Slots 2+: User-defined functions (skip imports) }
  for i := 0 to numFuncs - 1 do
    if funcs[i].bodyStart <> -2 then
      SmallEmitULEB128(secFunc, funcs[i].typeidx);
end;

procedure AssembleMemorySection;
begin
  SmallBufInit(secMemory);
  SmallBufEmit(secMemory, 1);    { 1 memory }
  SmallBufEmit(secMemory, 1);    { flags: has max }
  SmallBufEmit(secMemory, 1);    { initial: 1 page (64KB) }
  SmallEmitULEB128(secMemory, 256); { max: 256 pages (16MB) }
end;

procedure AssembleGlobalSection;
const
  MaxDisplayDepth = 8;
var
  i: longint;
begin
  SmallBufInit(secGlobal);
  SmallBufEmit(secGlobal, 1 + MaxDisplayDepth); { $sp + 8 display globals }
  { Global 0: $sp (stack pointer) }
  SmallBufEmit(secGlobal, WasmI32);  { type: i32 }
  SmallBufEmit(secGlobal, 1);        { mutable }
  { init expr: i32.const 65536 (top of 1 page) }
  SmallBufEmit(secGlobal, OpI32Const);
  { 65536 as SLEB128 }
  SmallBufEmit(secGlobal, $80);
  SmallBufEmit(secGlobal, $80);
  SmallBufEmit(secGlobal, $04);
  SmallBufEmit(secGlobal, OpEnd);
  { Globals 1..8: display[0]..display[7] — frame pointers for nested scopes }
  for i := 1 to MaxDisplayDepth do begin
    SmallBufEmit(secGlobal, WasmI32);  { type: i32 }
    SmallBufEmit(secGlobal, 1);        { mutable }
    SmallBufEmit(secGlobal, OpI32Const);
    SmallBufEmit(secGlobal, 0);        { init to 0 }
    SmallBufEmit(secGlobal, OpEnd);
  end;
end;

procedure AssembleExportSection;
var
  i, j: longint;
begin
  SmallBufInit(secExport);
  SmallEmitULEB128(secExport, 2 + numUserExports); { _start + memory + user exports }
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

procedure CopyBufToCode(var src: TCodeBuf);
var i: longint;
begin
  for i := 0 to src.len - 1 do
    CodeBufEmit(secCode, src.data[i]);
end;

procedure AssembleCodeSectionFixed;
{** Assemble the code section.
  Function order: slot 0 = _start, slot 1 = __write_int, slots 2+ = user funcs. }
var
  bodyLen: longint;
  i, j: longint;
begin
  CodeBufInit(secCode);

  { Function count }
  EmitULEB128(secCode, numDefinedFuncs);

  { Slot 0: _start body — 0 locals + code + end }
  bodyLen := 1 + startCode.len + 1;
  EmitULEB128(secCode, bodyLen);
  CodeBufEmit(secCode, 0);  { 0 local declarations }
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

  { Slots 2+: User-defined function bodies (skip imports) }
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
  WriteOutputBytes(tmp.data, tmp.len);
  WriteOutputBytes(secData.data, secData.len);
end;

procedure WriteModule;
begin
  CodeBufInit(outBuf);

  { Pre-register all WASM types before assembling sections }
  TypeVoidVoid;
  TypeI32Void;  { always needed for __write_int stub and proc_exit }

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
  WriteSection(SecIdType, secType.data, secType.len);
  WriteSection(SecIdImport, secImport.data, secImport.len);
  WriteSection(SecIdFunc, secFunc.data, secFunc.len);
  WriteSection(SecIdMemory, secMemory.data, secMemory.len);
  WriteSection(SecIdGlobal, secGlobal.data, secGlobal.len);
  WriteSection(SecIdExport, secExport.data, secExport.len);
  WriteSection(SecIdCode, secCode.data, secCode.len);
  AssembleDataSection; { writes directly to outBuf }

  { Flush to file }
  Assign(outFile, '/dev/stdout');
  Rewrite(outFile, 1);
  BlockWrite(outFile, outBuf.data, outBuf.len);
  Close(outFile);
end;

{ ---- Main ---- }

procedure Init;
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
  numImports := 0;
  numDefinedFuncs := 2; { slot 0 = _start, slot 1 = __write_int (reserved) }
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

  needsFdWrite := false;
  needsFdRead := false;
  needsProcExit := false;
  needsWriteInt := false;

  hasPendingImport := false;
  hasPendingExport := false;
  numUserExports := 0;

  { Pre-register all WASI imports so numImports is stable before
    any code emission. WASI hosts always provide these functions. }
  idxFdWrite := AddImport('wasi_snapshot_preview1', 'fd_write', TypeI32x4I32);
  idxFdRead := -1;  { TODO: register when read/readln is implemented }
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

  { Assemble and write WASM module }
  WriteModule;
end.
