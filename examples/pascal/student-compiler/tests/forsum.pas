program forsum;
var i, s: integer;
begin
  s := 0;
  for i := 1 to 10 do
    s := s + i;
  halt(s)
end.
