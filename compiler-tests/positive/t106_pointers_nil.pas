{ nil is address zero and compares only with = and <>. A pointer that has
  been set to nil must compare equal to it, and one pointing at a variable
  must not. }
program t106;
type PInt = ^integer;
var
  i: integer;
  p: PInt;
begin
  i := 5;
  p := nil;
  if p = nil then writeln('nil');
  if not (p <> nil) then writeln('still nil');
  p := @i;
  if p <> nil then writeln('set');
  if p = @i then writeln('same target');
  p := nil;
  if p = nil then writeln('cleared');
end.
