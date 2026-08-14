unit Base;
interface
function Two: integer;
procedure Say(const s: string);
implementation
function Two: integer; begin Two := 2 end;
procedure Say(const s: string); begin writeln('base: ', s) end;
end.
