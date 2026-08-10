{ A method's symbol name is built from its receiver's unit-qualified type
  name, not from where the type's descriptor happened to land. Two types
  called TR in different scopes must keep their own methods, and an alias
  must share the methods of the type it names.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program t131;
type
  TR = record
    W: integer;
  end;
  TAlias = TR;

function Area for (r: TR): integer;
begin
  Area := r.W
end;

procedure Inner;
type
  TR = record
    W, H: integer;
  end;

  function Area for (r: TR): integer;
  begin
    Area := r.W * r.H
  end;

var
  q: TR;
begin
  q.W := 3;
  q.H := 4;
  writeln('inner ', q.Area)
end;

var
  g: TR;
  a: TAlias;
begin
  g.W := 7;
  writeln('outer ', g.Area);
  a.W := 5;
  writeln('alias ', a.Area);
  Inner
end.
