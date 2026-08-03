program n018;
type PInt = ^integer;
var p: PInt; i: integer;
begin
  i := 1;
  p := @i;
  writeln(p);
end.
