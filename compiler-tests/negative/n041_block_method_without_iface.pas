{ A method defined in an implement block is not dot-callable on the concrete
  type either, so the message names the interface rather than the record.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n041;
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
    F := 1
  end;
end;

begin
  writeln(F)
end.
