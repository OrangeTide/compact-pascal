{ Without `uses Files` the file routines are not built in, so a program may
  use those names for its own things. They were unconditional before system
  units existed, and a procedure named Close was simply unreachable. }
program t122;
var
  assign: integer;
  reset: string;

procedure Close(n: integer);
begin
  writeln('closing ', n);
end;

function Rewrite(s: string): string;
begin
  Rewrite := s + '!';
end;

begin
  assign := 7;
  reset := 'a name, not a routine';
  writeln(reset);
  Close(assign);
  writeln(Rewrite('rewritten'));
end.
