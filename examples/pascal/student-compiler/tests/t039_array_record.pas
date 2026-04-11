program t039_array_record;
type
  TPoint = record
    x: integer;
    y: integer;
  end;
  TPoints = array[1..3] of TPoint;
var
  pts: TPoints;
  i: integer;
begin
  for i := 1 to 3 do begin
    pts[i].x := i * 10;
    pts[i].y := i * 10 + 1;
  end;
  for i := 1 to 3 do
    writeln(pts[i].x, ' ', pts[i].y);
end.
