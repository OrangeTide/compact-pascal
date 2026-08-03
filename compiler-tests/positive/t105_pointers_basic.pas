{ Pointers to existing storage: address-of, dereference, assignment through
  a dereference, and pointers to records and array elements. No heap is
  involved; every target is a variable that already exists. }
program t105;
type
  PInt = ^integer;
  TRec = record a, b: integer; end;
  PRec = ^TRec;
var
  i: integer;
  p: PInt;
  r: TRec;
  q: PRec;
  xs: array[1..3] of integer;
  ps: array[1..3] of PInt;
  k: integer;
begin
  i := 42;
  p := @i;
  writeln(p^);
  p^ := 7;
  writeln(i);

  r.a := 1;
  r.b := 2;
  q := @r;
  writeln(q^.a, ' ', q^.b);
  q^.b := 99;
  writeln(r.b);

  for k := 1 to 3 do begin
    xs[k] := k * k;
    ps[k] := @xs[k];
  end;
  for k := 1 to 3 do
    write(ps[k]^, ' ');
  writeln;
  ps[2]^ := 100;
  writeln(xs[2]);
end.
