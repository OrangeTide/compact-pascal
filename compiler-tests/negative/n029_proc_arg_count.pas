{ Calling a procedural value with the wrong number of arguments is caught at
  the call site, not left to trap.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n029;
type
  TBinOp = function(a, b: integer): integer;
var
  f: TBinOp;

function Add(a, b: integer): integer;
begin
  Add := a + b
end;

begin
  f := @Add;
  writeln(f(1))
end.
