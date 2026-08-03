{ A loop whose body or condition calls a string-returning function must not
  walk the stack down one result buffer at a time. Each iteration releases
  what it took.

  10000 iterations against a 64 KB stack: without the per-iteration release
  this exhausts the stack and traps on the overflow guard long before it
  finishes. The exit path through break is checked too, since a branch skips
  the release the statement would have run. }
program t112;
function Label_(n: integer): string;
begin
  if n mod 2 = 0 then Label_ := 'even' else Label_ := 'odd';
end;
var i, evens: integer;
    s: string;
begin
  evens := 0;
  for i := 1 to 10000 do
    if Label_(i) = 'even' then evens := evens + 1;
  writeln('evens ', evens);

  i := 0;
  while i < 5000 do begin
    s := Label_(i);
    i := i + 1;
  end;
  writeln('last ', s);

  i := 0;
  repeat
    s := Label_(i) + '!';
    i := i + 1;
  until i >= 5000;
  writeln('repeat ', s);

  for i := 1 to 10000 do begin
    if Label_(i) = 'odd' then continue;
    if i > 9000 then break;
  end;
  writeln('broke at ', i);
end.
