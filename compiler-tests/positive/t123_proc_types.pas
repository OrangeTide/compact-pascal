{ Procedural types: taking a routine's address, calling through the value,
  and passing one as a parameter.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program t123;
type
  TBinOp = function(a, b: integer): integer;
  TAction = procedure(n: integer);

var
  f: TBinOp;
  p: TAction;

function Add(a, b: integer): integer;
begin
  Add := a + b
end;

function Mul(a, b: integer): integer;
begin
  Mul := a * b
end;

procedure Show(n: integer);
begin
  writeln('n=', n)
end;

function Apply(op: TBinOp; x, y: integer): integer;
begin
  Apply := op(x, y)
end;

var
  i: integer;
begin
  f := @Add;
  writeln(f(3, 4));
  f := @Mul;
  writeln(f(3, 4));

  p := @Show;
  p(42);

  writeln(Apply(@Add, 10, 3));
  writeln(Apply(@Mul, 10, 3));
  writeln(Apply(f, 5, 6));

  { The same routine's address taken twice is one table entry, and a value
    survives being copied through another variable. }
  for i := 1 to 3 do begin
    f := @Add;
    writeln(Apply(f, i, i))
  end
end.
