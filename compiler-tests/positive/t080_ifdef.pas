program t080_ifdef;

{$IFDEF FPC}
procedure FpcProc;
begin
  writeln('fpc');
end;
{$ELSE}
procedure FpcProc;
begin
  writeln('self');
end;
{$ENDIF}

begin
  { IFDEF true branch }
  {$IFDEF FPC}
  write('y');
  {$ELSE}
  write('n');
  {$ENDIF}

  { IFNDEF false branch (FPC is defined) }
  {$IFNDEF FPC}
  write('n');
  {$ELSE}
  write('y');
  {$ENDIF}

  { IFDEF without ELSE }
  {$IFDEF FPC}
  write('y');
  {$ENDIF}

  { IFNDEF without ELSE — skipped entirely }
  {$IFNDEF FPC}
  write('BUG');
  {$ENDIF}

  writeln;

  { Nested IFDEF }
  {$IFDEF FPC}
    {$IFDEF FPC}
    write('nested');
    {$ENDIF}
  {$ENDIF}
  writeln;

  { Procedure from conditional block }
  FpcProc;
end.
