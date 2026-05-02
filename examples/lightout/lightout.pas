program LightsOut;
{
  Made by a machine. PUBLIC DOMAIN (CC0-1.0)
  Light's Out browser game compiled to WASM.
  5x5 grid puzzle: click a cell to toggle it and its orthogonal neighbors.
  Win by clearing all lights.
}

const
  BoardSize = 25;         { 5x5 grid }
  GridWidth = 5;
  GridHeight = 5;
  NumLevels = 1;          { Start with 1 level for simplicity }

  { Animation states }
  stPlay = 0;
  stWinAnim = 1;
  stAdvance = 2;

  { Virtual canvas coordinates }
  CanvasWidth = 500;
  CanvasHeight = 600;

var
  board: array[0..24] of integer;
  level: integer;
  gameState: integer;
  winStartTime: integer;

{ ===== Imported host functions ===== }

{$IMPORT 'host' canvasClear}
procedure CanvasClear(r, g, b: integer); external;

{$IMPORT 'host' canvasFillRect}
procedure CanvasFillRect(x, y, w, h: integer; r, g, b: integer); external;

{$IMPORT 'host' audioPlayTone}
procedure AudioPlayTone(freqHz, durMs, offsetMs: integer); external;

{$IMPORT 'host' requestAnimFrame}
procedure RequestAnimFrame; external;

{$IMPORT 'host' getTimeMs}
function GetTimeMs: integer; external;

{ Forward declarations }
procedure Redraw; forward;
procedure DoMove(cellX, cellY: integer); forward;
procedure CheckWin; forward;
procedure PlayFanfare; forward;

{ ===== Exported callbacks ===== }

{$EXPORT init}
procedure Init;
var
  i: integer;
begin
  level := 0;
  gameState := stPlay;

  { Initialize board: set up a solvable pattern }
  for i := 0 to BoardSize - 1 do
    board[i] := 0;

  { Create a simple pattern }
  board[6] := 1;   { row 1, col 1 }
  board[8] := 1;   { row 1, col 3 }
  board[16] := 1;  { row 3, col 1 }
  board[18] := 1;  { row 3, col 3 }

  Redraw;
end;

{$EXPORT handleClick}
procedure HandleClick(vx, vy: integer);
var
  cellX, cellY: integer;
begin
  { Convert virtual coordinates to grid position }
  cellX := vx div 100;
  cellY := (vy - 100) div 100;

  { Check if click is within the board area }
  if cellX >= 0 then
    if cellX < GridWidth then
      if cellY >= 0 then
        if cellY < GridHeight then begin
          DoMove(cellX, cellY);
          Redraw;
          CheckWin;
        end;
end;

{$EXPORT stepAnimation}
function StepAnimation(elapsedMs: integer): integer;
var
  animIndex: integer;
begin
  if gameState <> stWinAnim then begin
    StepAnimation := 0;
    exit;
  end;

  { Continue animation for 2 seconds }
  if elapsedMs < 2000 then
    StepAnimation := 1
  else begin
    { Animation complete: advance to next level }
    level := level + 1;
    gameState := stPlay;
    Init;
    StepAnimation := 0;
  end;
end;

{ ===== Game Logic ===== }

procedure DoMove(cellX, cellY: integer);
var
  index: integer;
begin
  { Toggle the clicked cell and its orthogonal neighbors }
  index := cellY * GridWidth + cellX;

  { Toggle center }
  if board[index] = 0 then
    board[index] := 1
  else
    board[index] := 0;

  { Up neighbor }
  if cellY > 0 then begin
    if board[index - GridWidth] = 0 then
      board[index - GridWidth] := 1
    else
      board[index - GridWidth] := 0;
  end;

  { Down neighbor }
  if cellY < GridHeight - 1 then begin
    if board[index + GridWidth] = 0 then
      board[index + GridWidth] := 1
    else
      board[index + GridWidth] := 0;
  end;

  { Left neighbor }
  if cellX > 0 then begin
    if board[index - 1] = 0 then
      board[index - 1] := 1
    else
      board[index - 1] := 0;
  end;

  { Right neighbor }
  if cellX < GridWidth - 1 then begin
    if board[index + 1] = 0 then
      board[index + 1] := 1
    else
      board[index + 1] := 0;
  end;
end;

procedure CheckWin;
var
  i: integer;
  allOff: integer;
begin
  allOff := 1;
  for i := 0 to BoardSize - 1 do
    if board[i] <> 0 then
      allOff := 0;

  if allOff = 1 then begin
    gameState := stWinAnim;
    winStartTime := GetTimeMs;
    PlayFanfare;
    RequestAnimFrame;
  end;
end;

procedure PlayFanfare;
var
  offset: integer;
begin
  offset := 0;
  { C major scale: C E G C }
  AudioPlayTone(262, 150, offset);
  offset := offset + 150;
  AudioPlayTone(330, 150, offset);
  offset := offset + 150;
  AudioPlayTone(392, 150, offset);
  offset := offset + 150;
  AudioPlayTone(523, 300, offset);
end;

{ ===== Rendering ===== }

procedure Redraw;
var
  i, row, col: integer;
  x, y: integer;
  r, g, b: integer;
begin
  { Clear background to dark }
  CanvasClear(30, 30, 40);

  { Draw header }
  CanvasFillRect(0, 0, CanvasWidth, 100, 45, 45, 55);

  { Draw 5x5 grid of cells }
  for i := 0 to BoardSize - 1 do begin
    row := i div GridWidth;
    col := i mod GridWidth;

    { Cell position in virtual coordinates }
    x := col * 100;
    y := 100 + (row * 100);

    { Color: yellow if lit, dark if off }
    if board[i] <> 0 then begin
      r := 255;
      g := 220;
      b := 0;
    end else begin
      r := 60;
      g := 60;
      b := 70;
    end;

    { Draw cell with border }
    CanvasFillRect(x + 2, y + 2, 96, 96, r, g, b);
    CanvasFillRect(x + 10, y + 10, 80, 80, r, g, b);
  end;
end;

begin
  { Entry point - initialization will be called from JS }
end.
