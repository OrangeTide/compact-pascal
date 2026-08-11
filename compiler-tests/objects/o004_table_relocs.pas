{ A procedural value is a table slot, assigned per compilation from 1 upward.
  Two units both numbering from 1 collide, so each site records a table
  relocation for the linker to reassign.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
unit Ops;

interface

type
  TOp = function(a: integer): integer;

function Twice(a: integer): integer;
function Pick: TOp;

implementation

function Twice(a: integer): integer;
begin
  Twice := a * 2
end;

function Pick: TOp;
begin
  Pick := @Twice
end;

end.
