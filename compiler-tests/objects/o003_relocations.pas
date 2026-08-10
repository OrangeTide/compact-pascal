{ A routine that calls another records a func relocation at the call, because
  the callee's final index is only known once every unit is placed.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
unit Calls;

interface

function Twice(a: integer): integer;
function Quad(a: integer): integer;

implementation

function Twice(a: integer): integer;
begin
  Twice := a * 2
end;

function Quad(a: integer): integer;
begin
  Quad := Twice(Twice(a))
end;

end.
