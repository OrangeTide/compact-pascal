unit Geometry;

interface

const
  Origin = 0;
  Scale = 100;

function Distance(a, b: integer): integer;
procedure Reset(var a: integer; const b: integer);
function Near(a: integer): boolean;

implementation

function Distance(a, b: integer): integer;
begin
  Distance := a * a + b * b
end;

procedure Reset(var a: integer; const b: integer);
begin
  a := b
end;

function Near(a: integer): boolean;
begin
  Near := a < 10
end;

end.
