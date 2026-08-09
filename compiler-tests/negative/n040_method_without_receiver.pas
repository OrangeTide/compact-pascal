{ A method is not a name in ordinary scope. Reporting it as undeclared sends
  the reader looking for a declaration that is sitting right there, so the
  message says where the name actually lives.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program n040;
type
  TR = record
    W: integer;
  end;

function Area for (r: TR): integer;
begin
  Area := r.W
end;

var
  q: TR;
begin
  q.W := 1;
  writeln(Area(q))
end.
