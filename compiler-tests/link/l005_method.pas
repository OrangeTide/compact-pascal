{ A standalone method on an imported record type. The method's symbol name is
  rebuilt from the type descriptor the importer created, which only matches
  because method names are keyed on the unit-qualified type name.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program l005;

uses MethU;

var
  r: TR;
begin
  r := MakeR(5);
  writeln(r.Area)
end.
