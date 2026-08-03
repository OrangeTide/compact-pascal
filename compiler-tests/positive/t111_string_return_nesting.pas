{ A concatenation whose operand is a call, where the callee concatenates too.

  The pieces of a pending concatenation were held in one static array, so the
  callee overwrote the caller's while the caller was still using them. This
  compiled to the wrong answer long before functions could return strings; a
  named string return type reached it by accident. The pieces are now copied
  onto the stack across a call.

  Recursion is the same hazard one level further: every depth wants the same
  slots at the same time. }
program t111;
function Wrap(const s: string): string;
begin
  Wrap := '(' + s + ')';
end;
function Rep(s: string; n: integer): string;
begin
  if n <= 0 then Rep := ''
  else Rep := s + Rep(s, n - 1);
end;
var a, b: string;
begin
  a := 'A';
  b := 'B';
  writeln(a + Wrap(b));
  writeln(Wrap(a) + Wrap(b));
  writeln(a + Wrap(b + Wrap(a)));
  writeln('[', Rep('ab', 0), ']');
  writeln('[', Rep('ab', 3), ']');
  writeln(Rep('-', 2) + Wrap(Rep('x', 3)));
end.
