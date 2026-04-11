program t047_enum;

type
  Color = (Red, Green, Blue, Yellow);
  Day = (Mon, Tue, Wed, Thu, Fri, Sat, Sun);

var
  c: Color;
  d: Day;

begin
  writeln(Red);            { 0 }
  writeln(Green);          { 1 }
  writeln(Blue);           { 2 }
  writeln(Yellow);         { 3 }

  c := Green;
  if c = Green then
    writeln('green ok');

  c := Blue;
  writeln(c);              { 2 }
  if c <> Red then
    writeln('not red ok');

  d := Fri;
  writeln(d);              { 4 }

  if Sat > Fri then
    writeln('sat > fri');
end.
