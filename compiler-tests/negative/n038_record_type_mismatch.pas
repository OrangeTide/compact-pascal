{ Structured assignment copied a fixed number of bytes with no type check, so
  unrelated record types could be assigned to one another.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n038;
type
  TA = record
    X: integer;
  end;

  TB = record
    Y, Z: integer;
  end;

var
  a: TA;
  b: TB;
begin
  b.Y := 1;
  b.Z := 2;
  a := b;
  writeln(a.X)
end.
