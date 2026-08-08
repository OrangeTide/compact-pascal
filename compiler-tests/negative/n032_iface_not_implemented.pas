{ A record cannot be converted to an interface it has no implement block for.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n032;
type
  IPet = interface
    Speak: procedure;
  end;

  TRock = record
    Mass: integer;
  end;

var
  r: TRock;
  p: IPet;
begin
  r.Mass := 1;
  p := r
end.
