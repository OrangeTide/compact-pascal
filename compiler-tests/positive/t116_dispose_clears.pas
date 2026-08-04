{ dispose clears the pointer, so disposing twice traps on the nil check
  rather than pushing the same block onto the free list a second time and
  corrupting it. Standard Pascal leaves the pointer dangling and this case
  is undefined; making it loud costs one comparison.

  The directive keeps the check on during the suite's checks-off run. }
{$S+}
program t116;
type PI = ^integer;
var p: PI;
begin
  new(p);
  p^ := 7;
  writeln(p^);
  dispose(p);
  writeln('cleared: ', p = nil);
  dispose(p);
  writeln('unreachable: the second dispose should have trapped');
end.
