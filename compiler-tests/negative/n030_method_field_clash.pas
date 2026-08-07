{ A method may not share a name with a field of its receiver type, or
  MyCat.Name would be ambiguous.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n030;
type
  TCat = record
    Name: string[20];
  end;

function Name for (c: TCat): string;
begin
  Name := 'x'
end;

begin
end.
