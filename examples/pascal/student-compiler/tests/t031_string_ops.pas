program t031_string_ops;
var
  s: string[20];
  t: string[20];
  n: integer;
begin
  s := 'Hello';
  t := concat(s, ', world!');
  writeln(t);
  n := length(t);
  writeln(n);
  writeln(copy(t, 1, 5));
  writeln(pos('world', t));
end.
