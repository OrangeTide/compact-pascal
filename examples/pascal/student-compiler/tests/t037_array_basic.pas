program t037_array_basic;
var
  a: array[1..5] of integer;
  i: integer;
begin
  for i := 1 to 5 do
    a[i] := i * i;
  for i := 1 to 5 do
    writeln(a[i]);
end.
