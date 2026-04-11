program repeattest;
var n: integer;
begin
  n := 1;
  repeat
    n := n * 2
  until n >= 64;
  halt(n)
end.
