{ A for loop whose body calls a routine containing its own for loop. The limit
  used to live in a data slot indexed by lexical nesting depth, which is not
  unique at run time: the inner loop had the same depth as the outer and
  overwrote its limit. This loop ran eight times instead of once.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program t133;
var
  n, m, i, outer: integer;

function Inner: integer;
var
  k, t: integer;
begin
  t := 0;
  for k := 1 to m do
    t := t + k;
  Inner := t
end;

begin
  n := 1;
  m := 5;
  outer := 0;
  for i := 0 to n - 1 do begin
    outer := outer + 1;
    m := Inner
  end;
  writeln('outer ran ', outer);

  { And downto, which had the same slot and the same fault. }
  m := 4;
  outer := 0;
  for i := 2 downto 1 do begin
    outer := outer + 1;
    m := Inner
  end;
  writeln('downto ran ', outer)
end.
