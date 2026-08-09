{ An argument count that does not match the declaration was never checked.
  The call emitted a module that failed WASM validation instead.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n035;

function F(a, b: integer): integer;
begin
  F := a + b
end;

begin
  writeln(F(1))
end.
