{ A program calling into a separately compiled unit: an imported constant, an
  imported function, a chain of calls private to the unit, and string
  literals living in the unit's own data.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program l002;

uses Geometry;

var
  p: TPoint;
begin
  p.x := 3;
  p.y := 4;
  Show('dims', Dimensions);
  Show('distance', Distance(p.x, p.y));
  Show('quad', Quad(5))
end.
