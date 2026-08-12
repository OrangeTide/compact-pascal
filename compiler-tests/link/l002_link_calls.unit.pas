unit Geometry;
interface
const Dimensions = 2;
type TPoint = record x, y: integer end;
function Distance(a, b: integer): integer;
function Quad(a: integer): integer;
procedure Show(const label_: string; v: integer);
implementation
function Distance(a, b: integer): integer;
begin Distance := a * a + b * b end;
function Twice(a: integer): integer;
begin Twice := a * 2 end;
function Quad(a: integer): integer;
begin Quad := Twice(Twice(a)) end;
procedure Show(const label_: string; v: integer);
begin writeln(label_, ' = ', v) end;
end.
