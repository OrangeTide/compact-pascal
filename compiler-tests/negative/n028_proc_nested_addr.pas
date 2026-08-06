{ A nested routine reaches its parent frame through the display, so its
  address cannot be taken.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n028;
type
  TAction = procedure(n: integer);
var
  p: TAction;

procedure Outer;
  procedure Inner(n: integer);
  begin
    writeln(n)
  end;
begin
  p := @Inner
end;

begin
  Outer;
  p(1)
end.
