{ Source for the Debug: trace test. Exercises the traced events: a
  nested scope, declarations of several kinds, and a function body. }
program c005;
const Limit = 3;
var total: integer;

function Double(x: integer): integer;
begin
  Double := x * 2;
end;

begin
  total := Double(Limit);
  writeln(total);
end.
