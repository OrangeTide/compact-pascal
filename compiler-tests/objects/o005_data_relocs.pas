{ String literals and typed constants live in the data segment, and every
  address into it shifts when the linker concatenates segments. Each such
  push records a data relocation.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
unit Words;

interface

const
  Greeting = 'hello';

function Label_: string;
procedure Announce;

implementation

function Label_: string;
begin
  Label_ := Greeting
end;

procedure Announce;
var
  s: string;
begin
  s := 'a literal';
  writeln(s, ' and ', Greeting)
end;

end.
