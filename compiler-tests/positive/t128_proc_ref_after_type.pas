{ A type block appearing after a routine whose address is taken must not
  disturb the function table. Resolving forward pointers used to reset the
  table, which silently reassigned every index.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program t128;
type
  TOp = function(a: integer): integer;
var
  f, g: TOp;

function Inc1(a: integer): integer;
begin
  Inc1 := a + 1
end;

function Inc2(a: integer): integer;
type
  TInner = record
    x: integer;
  end;
var
  r: TInner;
begin
  r.x := 2;
  Inc2 := a + r.x
end;

begin
  f := @Inc1;
  g := @Inc2;
  writeln(f(10), ' ', g(10))
end.
