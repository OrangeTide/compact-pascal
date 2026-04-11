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
  writeln(p.x);
  writeln(p.y);
end.
