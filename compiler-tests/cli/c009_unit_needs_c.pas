{ A unit becomes an object and a program becomes a module. Neither can be
  asked to be the other, and the header is where to say so.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
unit Geometry;

interface

function Distance(a, b: integer): integer;

implementation

function Distance(a, b: integer): integer;
begin
  Distance := a * a + b * b
end;

end.
