{ Calls that are correct must stay correct now that arity is checked: a
  parameterless routine called without parentheses, a parameterless method,
  a method with parameters, and a structured result assigned rather than
  discarded.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program t130;
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

function Tag for (r: TR): string;
begin
  Tag := 'tagged'
end;

procedure Announce;
begin
  writeln('announced')
end;

var
  q: TR;
  s: string;
begin
  q.W := 6;
  Announce;
  writeln(q.Area);
  writeln(q.Plus(4));
  s := q.Tag;
  writeln(s)
end.
