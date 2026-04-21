program TypedConstRecord;
type
  TPoint = record
    x: integer;
    y: integer
  end;
  TPerson = record
    age: integer;
    name: string[10]
  end;
const
  origin: TPoint = (x: 0; y: 0);
  p1: TPoint = (x: 3; y: 4);
  alice: TPerson = (age: 30; name: 'Alice');
begin
  writeln(origin.x);
  writeln(origin.y);
  writeln(p1.x);
  writeln(p1.y);
  writeln(alice.age);
  writeln(alice.name)
end.
