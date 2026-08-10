{ A program compiled twice, once with five-byte immediates. Only the sizes
  should differ. Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program PadTest;
var i, n: integer; s: string;
function Twice(a: integer): integer; begin Twice := a * 2 end;
begin
  n := 0;
  for i := 1 to 5 do
    n := n + Twice(i);
  writeln('sum ', n);
  writeln('neg ', -1234567, ' big ', 2000000000);
  s := 'hello';
  writeln(s, ' ', length(s))
end.
