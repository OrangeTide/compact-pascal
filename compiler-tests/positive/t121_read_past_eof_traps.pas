{ The other half of t120: with I/O checks on, reading past the end traps
  rather than being recorded. }
{$FILES ON}
{$S+}
program t121;
var f: text;
    c: char;
begin
  assign(f, 't121.tmp');
  rewrite(f);
  write(f, 'x');
  close(f);
  assign(f, 't121.tmp');
  reset(f);
  while not eof(f) do read(f, c);
  read(f, c);
  writeln('unreachable: reading past the end should have trapped');
end.
