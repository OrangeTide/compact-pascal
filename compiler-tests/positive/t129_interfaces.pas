{ Interfaces: an implement block satisfied by a standalone method and by a
  method defined in the block, implicit conversion, dynamic dispatch, and an
  interface passed as a parameter.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program t129;
type
  IPet = interface
    Speak: procedure;
    Legs: function: integer;
  end;

  TCat = record
    Name: string[20];
  end;

  TBird = record
    Song: string[20];
  end;

procedure Speak for (c: TCat);
begin
  writeln('Meow from ', c.Name)
end;

implement IPet for TCat;

  { Speak is satisfied by the standalone method above and is not repeated. }
  function Legs: integer;
  begin
    Legs := 4
  end;

end;

implement IPet for TBird;

  procedure Speak;
  begin
    writeln('Tweet: ', Self^.Song)
  end;

  function Legs: integer;
  begin
    Legs := 2
  end;

end;

procedure Describe(const Pet: IPet);
begin
  Pet.Speak;
  writeln(Pet.Legs, ' legs')
end;

var
  c: TCat;
  b: TBird;
  p, q: IPet;
begin
  c.Name := 'Felix';
  b.Song := 'trill';

  p := c;
  Describe(p);

  p := b;
  Describe(p);

  { Interface to interface is a copy, not a conversion. }
  q := p;
  Describe(q)
end.
