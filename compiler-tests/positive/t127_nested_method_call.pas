{ A method call inside another method call's argument list. Each needs its own
  receiver slot; one shared local made the outer call run with the inner
  call's receiver.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program t127;
type
  TR = record
    W: integer;
  end;

function Area for (r: TR): integer;
begin
  Area := r.W
end;

function Plus for (r: TR) (k: integer): integer;
begin
  Plus := r.W + k
end;

var
  a, b, c: TR;
begin
  a.W := 10;
  b.W := 3;
  c.W := 1;
  writeln(a.Plus(b.Area));
  writeln(a.Plus(b.Plus(c.Area)))
end.
