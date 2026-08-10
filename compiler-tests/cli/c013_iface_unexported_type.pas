{ A field or parameter in the interface whose type the interface does not
  export would cross as a reference an importer could not resolve. The
  anonymous pointer type here is not exported and cannot be.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
unit Leaky;

interface

type
  TPub = record
    p: ^integer;
  end;

function G(r: TPub): integer;

implementation

function G(r: TPub): integer;
begin
  G := r.p^
end;

end.
