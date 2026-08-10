{ The unit header and the interface section parse under -c. The
  implementation section is the rest of the phase and says so.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
unit Geometry;

interface

const
  Origin = 0;

type
  TPoint = record
    x, y: integer;
  end;

function Distance(a, b: integer): integer;

implementation

function Distance(a, b: integer): integer;
begin
  Distance := a * a + b * b
end;

end.
