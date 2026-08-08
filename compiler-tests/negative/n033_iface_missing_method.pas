{ An implement block that leaves an interface signature unsatisfied is
  rejected when the block closes.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n033;
type
  IPet = interface
    Speak: procedure;
    Legs: function: integer;
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

begin
end.
