program recurse;

function fact(n: integer): integer;
begin
  if n <= 1 then
    fact := 1
  else
    fact := n * fact(n - 1);
end;

begin
  halt(fact(5));
end.
