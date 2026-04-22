program t097_typed_const_set_subrange;

{ Typed constants initialized with subrange-based set types. }

type
  Digits = set of 0..9;
  Day    = (Mon, Tue, Wed, Thu, Fri, Sat, Sun);
  Work   = set of Mon..Fri;

const
  Odds: Digits = [1, 3, 5, 7, 9];
  Weekdays: Work = [Mon, Tue, Wed, Thu, Fri];

var
  i: integer;
  d: Day;
begin
  for i := 0 to 9 do
    if i in Odds then write('1') else write('0');
  writeln;

  for d := Mon to Sun do
    if d in Weekdays then write('1') else write('0');
  writeln;
end.
