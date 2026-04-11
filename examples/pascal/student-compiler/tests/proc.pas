program proc;

procedure greet;
begin
  writeln('hello from proc');
end;

procedure add_and_print(a, b: integer);
var c: integer;
begin
  c := a + b;
  writeln(c);
end;

begin
  greet;
  add_and_print(3, 4);
end.
