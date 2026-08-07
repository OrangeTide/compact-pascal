{ A pointer-receiver method needs an address, and a function result is a
  temporary that has none.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n031;
type
  TP = record
    X: integer;
  end;

procedure Move for (p: ^TP) (d: integer);
begin
  p^.X := p^.X + d
end;

function Origin: TP;
var
  t: TP;
begin
  t.X := 0;
  Origin := t
end;

begin
  Origin.Move(1)
end.
