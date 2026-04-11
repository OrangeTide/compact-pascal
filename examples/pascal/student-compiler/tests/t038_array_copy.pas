program t038_array_copy;
var
  a, b: array[1..3] of integer;
  i: integer;
begin
  for i := 1 to 3 do
    a[i] := i;
  b := a;
  b[2] := 99;
  for i := 1 to 3 do
    writeln(a[i]);
  for i := 1 to 3 do
    writeln(b[i]);
end.
