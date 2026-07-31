{ The Language Reference specifies "Error: line:col: message" for
  diagnostics. This test pins that format, including the position, so a
  change back to the old "Error: [line:col] message" form is caught.
  The undeclared identifier below sits at a fixed line and column. }
program n010;
var
  x: integer;
begin
  x := bogus;
end.
