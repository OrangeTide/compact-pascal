program n007_set_enum_oor;
type
  Day   = (Mon, Tue, Wed, Thu, Fri);
  Mood  = (Sad, Ok, Happy);
  { Mix bounds from different enum types — bounds must share a type. }
  Bad   = set of Mon..Happy;
var s: Bad;
begin
  s := [];
end.
