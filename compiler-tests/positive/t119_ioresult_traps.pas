{ The other half of t118: with I/O checks on, a failed open traps rather than
  being silently recorded. A program that never asks about IOResult should
  not carry on with a file it does not have. }
{$S+}
program t119;
uses Files;
var f: text;
begin
  assign(f, 'no-such-file-t119.tmp');
  reset(f);
  writeln('unreachable: the open should have trapped');
end.
