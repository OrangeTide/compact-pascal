{ Dereferencing nil must trap rather than read the four-byte nil guard and
  hand back a zero the program never stored. The directive keeps the check
  on during the suite's checks-off run, where that is the whole point.
  With checks off this program prints 0 and exits normally, which is the
  behavior the check exists to replace. }
{$S+}
program t108;
type PInt = ^integer;
var p: PInt;
begin
  p := nil;
  writeln(p^);
end.
