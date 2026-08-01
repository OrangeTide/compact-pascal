{ -2147483648 has no positive counterpart in i32, so the integer formatter
  must not negate it. Both writeln and str once produced digit characters
  below '0' for this value because 0 - INT_MIN overflows back to itself. }
program t101;
var
  a: integer;
  s: string;
begin
  a := -2147483647;
  a := a - 1;
  writeln(a);
  str(a, s);
  writeln(s);
  writeln(2147483647);
  writeln(0);
  writeln(-1);
  writeln(-10);
end.
