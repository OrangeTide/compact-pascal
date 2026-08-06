{ Procedural values compare equal when they hold the same routine, because a
  routine occupies one table slot however often its address is taken.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program t125;
type
  TBinOp = function(a, b: integer): integer;
var
  f, g: TBinOp;

function Add(a, b: integer): integer;
begin
  Add := a + b
end;

function Mul(a, b: integer): integer;
begin
  Mul := a * b
end;

begin
  f := @Add;
  g := @Add;
  if f = g then writeln('same');
  g := @Mul;
  if f <> g then writeln('different')
end.
