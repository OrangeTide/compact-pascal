{ A procedural type imported from a unit. Its signature lives in fields the
  type record did not write, so the first call through one reported the wrong
  argument count.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program l004;

uses ProcU;

var
  f: TOp;
begin
  f := Pick;
  writeln(f(21))
end.
