unit Geometry;
interface
const
  Dimensions = 2;
type
  TPoint = record x, y: integer end;
function Distance(a, b: integer): integer;
implementation
function Distance(a, b: integer): integer;
begin Distance := a * a + b * b end;
end.
