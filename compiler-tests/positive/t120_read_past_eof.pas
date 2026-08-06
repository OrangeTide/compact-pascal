{ Reading past the end of a file is an error, not a quiet chr(0).

  A zero byte is a legal thing to find in a file, so handing one back for
  "there was nothing there" leaves a program no way to tell the two apart.
  Turbo Pascal makes this runtime error 100 for the same reason.

  The first loop shows what is being protected: a file containing a NUL
  reads back exactly, because a correct loop tests Eof and never reaches
  the end-of-file case at all. }
program t120;
uses Files;
var f: text;
    c: char;
    n: integer;
begin
  assign(f, 't120.tmp');
  rewrite(f);
  write(f, 'a');
  write(f, chr(0));
  write(f, 'b');
  close(f);

  assign(f, 't120.tmp');
  reset(f);
  n := 0;
  while not eof(f) do begin
    read(f, c);
    n := n + 1;
    write(ord(c), ' ');
  end;
  writeln;
  writeln('bytes ', n);

{$I-}
  read(f, c);
{$I+}
  writeln('past the end: ', IOResult);
  writeln('cleared: ', IOResult);
  close(f);
end.
