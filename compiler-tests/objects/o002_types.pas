unit Shapes;

interface

type
  TPoint = record
    x, y: integer;
  end;

  TRect = record
    lo, hi: TPoint;
    tag: char;
  end;

  TRow = array[1..4] of integer;

const
  MaxShapes = 8;

function Area(const r: TRect): integer;
procedure Move(var r: TRect; dx, dy: integer);
function Origin: TPoint;

implementation

function Area(const r: TRect): integer;
begin
  Area := (r.hi.x - r.lo.x) * (r.hi.y - r.lo.y)
end;

procedure Move(var r: TRect; dx, dy: integer);
begin
  r.lo.x := r.lo.x + dx;
  r.lo.y := r.lo.y + dy
end;

function Origin: TPoint;
var p: TPoint;
begin
  p.x := 0; p.y := 0;
  Origin := p
end;

end.
