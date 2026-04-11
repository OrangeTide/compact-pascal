# Chapter 2 Implementation Plan: The Scanner

## What Chapter 1 Already Provides

Chapter 1 built most of the scanner as scaffolding. These pieces are complete and do **not** need to change:

- `ReadCh` / `UnreadCh` — character input with one-character pushback
- `srcLine`, `srcCol` — position tracking for error messages
- `SkipWhitespaceAndComments` — handles `{ }`, `(* *)`, `//`, and shebang (`#!`) lines
- `SkipBraceComment`, `SkipParenComment`, `SkipLineComment`
- `UpperCh`, `LookupKeyword` — case-insensitive keyword recognition
- Identifiers and keyword dispatch in `NextToken`
- Decimal and hexadecimal integer literals
- All single- and double-character operator tokens
- `Error` procedure — halt-on-first-error with line:col

## What Chapter 2 Adds

### 1. String literal scanning (`'...'`)

String literals are delimited by single quotes. A literal single-quote inside the
string is represented by two consecutive single-quotes (`''`).

Algorithm inside `NextToken`, case `''''`:
```
ident := ''
ReadCh  { consume opening quote, ch = first char inside }
loop:
  if atEof → Error('unterminated string')
  if ch = '''' then
    ReadCh
    if ch = '''' then   { doubled quote → literal ' }
      append '''' to ident
      ReadCh
    else                 { end of string }
      break
  else
    append ch to ident
    ReadCh
tokStr  := ident
tokKind := tkString
{ do NOT call ReadCh at end — ch already holds first char after closing quote }
```

After scanning a string token, check whether `ch` begins another string segment or
`#` character constant. If so, continue folding (see §3 below).

### 2. Character constants (`#n`, `#$n`)

The `#` token prefix (decimal or hex) produces a one-byte string value. It must
not be confused with the shebang check in `InitScanner`, which only fires at the
very first character of the file before any `NextToken` call.

Algorithm inside `NextToken`, case `'#'`:
```
ReadCh   { consume '#', ch = digit or '$' }
if ch = '$' then
  ReadCh; scan hex digits → val
else
  scan decimal digits → val
if val < 0 or val > 255 → Error('character constant out of range')
ident   := chr(val)
tokStr  := ident
tokKind := tkString
{ do NOT call ReadCh — ch already holds first char after the digits }
```

After scanning, check for adjacent segments (see §3).

### 3. Adjacent string/character folding

The scanner must fold adjacent string segments and `#` constants into a single
`tkString` token. This happens at the *scanner level*, so the parser always sees
one token per logical string.

After completing a string or `#` scan, before returning:
```
while (ch = '''') or (ch = '#') do begin
  if ch = '''' then scan another '...' segment, append to tokStr
  else          scan another #n segment, append chr(val) to tokStr
end
```

This loop repeats until neither `'` nor `#` follows.

### 4. Real number detection in `.` scanning

Currently the `.` case produces `tkDot` or `tkDotDot`. Chapter 2 adds detection
of real number syntax (`3.14`) so the error message is clear. This check belongs
in the *integer* scanning case, not the `.` case:

After scanning a decimal integer, if `ch = '.'`:
```
ReadCh  { peek at char after dot }
if (ch >= '0') and (ch <= '9') then
  Error('real numbers are not supported')
else
  UnreadCh(ch)   { put back non-digit; '.' belongs to next token }
  ch := '.'
```

The `.` case itself is unchanged — by the time we reach it the integer case has
already handled the real-number situation.

### 5. Two-word operators: `and then` / `or else`

Compact Pascal supports short-circuit operators as two-word tokens.

New token constants needed:
```pascal
tkAndThen = 135;
tkOrElse  = 136;
```

New global scanner state:
```pascal
var
  pendingTok:  boolean;
  pendingKind: longint;
  pendingStr:  string;
```

`NextToken` gets a new preamble:
```pascal
if pendingTok then begin
  tokKind    := pendingKind;
  tokStr     := pendingStr;
  pendingTok := false;
  exit;
end;
```

In the `tkAnd` branch of keyword dispatch, after setting `tokKind := tkAnd`,
peek ahead:
```pascal
{ peek for 'then' to form 'and then' }
NextToken;  { scan next token into tok* }
if tokKind = tkThen then
  tokKind := tkAndThen  { consume 'then', return combined token }
else begin
  { push current token back as pending }
  pendingTok  := true;
  pendingKind := tokKind;
  pendingStr  := tokStr;
  tokKind     := tkAnd;
end;
```

Apply the same pattern for `tkOr` / `or else` → `tkOrElse`.

**Note:** The pending mechanism stores at most one token. This is sufficient
because `and then` and `or else` are the only two-word lookaheads in the language.

### 6. `LookupKeyword` additions

`AND`, `OR`, `THEN`, `ELSE` are already in the keyword table. No additions needed
for two-word operators — the folding happens after keyword dispatch.

`ANDD` / `ORR` etc. are not keywords; no risk of collision.

## Data Structures: No Changes

All token variables (`tokKind`, `tokInt`, `tokStr`) and scanner state already
exist. The only new globals are `pendingTok`, `pendingKind`, `pendingStr`.

## Test Programs

### `tests/comments.pas` — multi-style comments
```pascal
{ brace comment }
(* paren-star comment *)
// line comment
program comments; (* mixed *)
{ nested text that mentions left-curly-brace and right-curly-brace }
begin
end.
```
Expected: compiles to valid WASM (parser just sees `program...begin end.`).

### `tests/empty.pas` — already exists, keep passing.

### Manual scanner smoke tests (not automated yet)

Until Chapter 3 adds expression parsing, string/integer tokens cannot appear in
a legal program body. These will be tested as part of Chapter 3's expression
tests. For now, confirm the scanner does not crash when the token stream includes
the new tokens in otherwise legal positions.

## Implementation Order

1. Add `tkAndThen`, `tkOrElse` constants
2. Add `pendingTok`, `pendingKind`, `pendingStr` globals
3. Add pending-token preamble to `NextToken`
4. Add string literal scanning (`''''` case)
5. Add character constant scanning (`'#'` case, post-shebang)
6. Add adjacent folding loop after string/char cases
7. Add real-number detection in the integer case
8. Add `and then` / `or else` lookahead in keyword dispatch
9. Add `tests/comments.pas` and run `make test`

## What Is NOT in Chapter 2

- Expression parsing or code generation — Chapter 3
- `writeln`, `halt` — Chapter 3/4
- `var`, assignments — Chapter 4
- Control flow — Chapter 5
- Directive parsing (`{$...}`) — Chapter 10

## Open Questions / Risks

- **`ident := concat(ident, ch)`**: confirmed working in FPC -Mtp mode (tested in
  Chapter 1). String folding will use the same pattern with `concat`.
- **String length limit**: `string` in TP mode is 255 bytes. A string literal
  longer than 255 chars will silently truncate. Add a length check in the scanner:
  if `length(tokStr) >= 255` before appending, emit an error.
- **`and then` in `LookupKeyword`**: `THEN` is returned as `tkThen`. The `and`
  keyword dispatch re-calls `NextToken` to peek. If the source is `and {comment}
  then`, the whitespace and comment are stripped before the peek — this is correct
  behaviour since `and then` is two words, not necessarily adjacent characters.
