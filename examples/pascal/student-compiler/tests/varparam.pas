program varparam;

procedure swap(var a, b: integer);
var tmp: integer;
begin
  tmp := a;
  a := b;
  b := tmp;
end;

var x, y: integer;
begin
  x := 3;
  y := 7;
  swap(x, y);
  writeln(x);
  writeln(y);
end.
