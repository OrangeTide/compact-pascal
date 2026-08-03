program n020;
{$IMPORT 'host' getName}
function GetName: string; external;
begin
  writeln(GetName);
end.
