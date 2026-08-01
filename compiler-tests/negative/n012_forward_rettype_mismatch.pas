{ A differing return type was accepted silently, leaving the caller to read
  the result as whatever the forward declaration promised. }
program n012;
function Q(a: integer): integer; forward;
function Q(a: integer): char;
begin
  Q := chr(a);
end;
begin
  writeln(Q(65));
end.
