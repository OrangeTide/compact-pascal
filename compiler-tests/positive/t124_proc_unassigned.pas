{ A procedural variable that was never assigned holds zero, and index zero of
  the table is empty, so calling it traps.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program t124;
type
  TAction = procedure(n: integer);
var
  never: TAction;
  p: TAction;

procedure Show(n: integer);
begin
  writeln('n=', n)
end;

begin
  p := @Show;
  p(1);
  writeln('about to call an unassigned procedural variable');
  never(2);
  writeln('unreachable')
end.
