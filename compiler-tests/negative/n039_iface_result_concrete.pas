{ A function returning an interface cannot be handed a concrete value: the
  conversion would point Self at a local that is about to die.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n039;
type
  IA = interface
    F: function: integer;
  end;

  TR = record
    N: integer;
  end;

implement IA for TR;
  function F: integer;
  begin
    F := Self^.N
  end;
end;

function Make: IA;
var
  r: TR;
begin
  r.N := 3;
  Make := r
end;

var
  a: IA;
begin
  a := Make;
  writeln(a.F)
end.
