{ A standalone method exports under its mangled name, which is built from the
  receiver's unit-qualified type name. An importer recreating the type from
  this same object rebuilds the identical key, so the method is findable.
  Exporting the plain name would export something no call site looks up.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
unit Geom;

interface

type
  TR = record
    w: integer;
  end;

function Area for (r: TR): integer;

implementation

function Area for (r: TR): integer;
begin
  Area := r.w
end;

end.
