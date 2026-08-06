{ A routine whose signature does not match the procedural type it is
  assigned to is rejected, rather than trapping at the indirect call.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n027;
type
  TBinOp = function(a, b: integer): integer;
var
  f: TBinOp;

function One(a: integer): integer;
begin
  One := a
end;

begin
  f := @One;
  writeln(f(1, 2))
end.
