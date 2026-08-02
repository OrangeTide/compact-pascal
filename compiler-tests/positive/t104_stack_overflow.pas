{ Runaway recursion must trap at the point the stack would overflow, not
  walk down through the heap and data segment corrupting them silently.
  The frame here is large enough that one subtraction would carry the
  stack pointer past zero, which is the case a naive check misses: a
  wrapped pointer compares as a huge address and looks fine. }
program t104;
procedure Recurse(n: integer);
var pad: array[1..8000] of integer;
begin
  pad[1] := n;
  Recurse(n + 1);
end;
begin
  Recurse(1);
  writeln('unreachable: the guard should have trapped');
end.
