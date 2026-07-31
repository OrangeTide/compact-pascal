{ An unrecognized compiler directive is skipped, but the compiler says so
  rather than letting a typo silently do nothing. The warning is not fatal:
  compilation continues and the program below runs normally. }
program t100;
{$RANGECHEKS ON}
begin
  writeln('compiled');
end.
