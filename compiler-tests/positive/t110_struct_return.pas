{ Records and arrays return the same way strings do: through a buffer the
  caller allocates and passes as a hidden trailing argument. }
program t110;
type
  TPoint = record x, y: integer end;
  TRow = array[1..3] of integer;
function MakePoint(a, b: integer): TPoint;
var t: TPoint;
begin
  t.x := a;
  t.y := b;
  MakePoint := t;
end;
function MakeRow(base: integer): TRow;
var r: TRow; i: integer;
begin
  for i := 1 to 3 do r[i] := base + i;
  MakeRow := r;
end;
var p: TPoint; row: TRow; i: integer;
begin
  p := MakePoint(3, 4);
  writeln(p.x, ' ', p.y);
  row := MakeRow(10);
  for i := 1 to 3 do write(row[i], ' ');
  writeln;
end.
