{ Opening a file that is not there.

  With I/O checks on, the default, the failure traps at the point it happens,
  which is what a program that never checks should get. With them off the
  error is recorded and IOResult hands it over once, then reads zero. The
  clearing is Turbo Pascal's contract and is the part worth pinning: it makes
  "did that work" a question with exactly one answer. }
program t118;
uses Files;
var f: text;
    e: integer;
begin
  assign(f, 'no-such-file-t118.tmp');
{$I-}
  reset(f);
{$I+}
  e := IOResult;
  writeln('failed: ', e <> 0);
  writeln('cleared: ', IOResult);
  close(f);
  writeln('close of an unopened file is harmless');
end.
