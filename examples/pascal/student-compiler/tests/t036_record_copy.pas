program t036_record_copy;
type
  TPoint = record x: integer; y: integer; end;
var
  a, b: TPoint;
begin
  a.x := 10;
  a.y := 20;
  b := a;
  b.x := 99;
  writeln(a.x);
  writeln(a.y);
  writeln(b.x);
  writeln(b.y);
end.
