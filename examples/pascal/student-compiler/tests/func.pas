program func;

function square(n: integer): integer;
begin
  square := n * n;
end;

function add(a, b: integer): integer;
begin
  add := a + b;
end;

begin
  halt(square(3) + add(1, 2));
end.
