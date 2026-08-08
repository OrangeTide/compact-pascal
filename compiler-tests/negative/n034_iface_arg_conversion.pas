{ A concrete record cannot be converted to an interface at a call site: the
  vtable has to be built somewhere, and assignment is the only place with
  storage for it.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n034;
type
  IPet = interface
    Speak: procedure;
  end;

  TCat = record
    Name: string[20];
  end;

procedure Speak for (c: TCat);
begin
  writeln('Meow')
end;

implement IPet for TCat;
end;

procedure Say(Pet: IPet);
begin
  Pet.Speak
end;

var
  c: TCat;
begin
  c.Name := 'F';
  Say(c)
end.
