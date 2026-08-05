{ A text file written, closed, reopened, and read back.

  Filesystem access is opt-in: without the directive the module does not
  import path_open, so a host can tell from the import list alone that a
  program wants files. See the FILES directive in the reference. }
{$FILES ON}
program t117;
var f: text;
    s: string;
    n: integer;
begin
  assign(f, 't117.tmp');
  rewrite(f);
  writeln(f, 'alpha');
  writeln(f, 'beta');
  writeln(f, 'count ', 42);
  close(f);

  assign(f, 't117.tmp');
  reset(f);
  n := 0;
  while not eof(f) do begin
    readln(f, s);
    n := n + 1;
    writeln(n, ': ', s);
  end;
  close(f);
end.
