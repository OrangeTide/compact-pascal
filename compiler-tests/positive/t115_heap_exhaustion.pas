{ The heap grows up from the data segment and the stack grows down from the
  top of memory. They share one boundary, so running out is a trap rather
  than an overlap that corrupts both.

  The directive keeps the check on during the suite's checks-off run. }
{$S+}
program t115;
type
  PBig = ^TBig;
  TBig = record pad: array[1..2048] of integer end;
var p: PBig;
    i: integer;
begin
  for i := 1 to 1000 do begin
    new(p);
    p^.pad[1] := i;
  end;
  writeln('unreachable: the heap should have met the stack');
end.
