program n019;
type TR = record a: integer end;
  PR = ^TR;
var r: TR; q: PR;
begin
  r.a := 3;
  q := @r;
  with q^ do writeln(a);
end.
