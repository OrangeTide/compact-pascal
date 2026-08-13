{ A unit has no frame, so a variable at its top level would be read out of
  whatever frame the program left behind. It compiled and did exactly that
  until this check existed.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
unit Counters;

interface

var
  Counter: integer;

procedure Bump;

implementation

procedure Bump;
begin
  Counter := Counter + 1
end;

end.
