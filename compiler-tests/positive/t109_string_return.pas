{ A function may return a string. The result is caller-allocated: the caller
  hands the callee a buffer and the callee writes into it, so two results
  live at once and neither points into a frame that has been released.

  Before this worked, a named string return type compiled by accident and
  returned the address of the callee's own local. The concatenation below is
  the case that exposed it: both calls returned the same dead frame slot, so
  F(1) + F(2) printed the second value twice. }
program t109;
function F(n: integer): string;
var buf: string;
begin
  buf := 'aaa';
  if n = 2 then buf := 'bbb';
  F := buf;
end;

function Greet(const name: string): string;
begin
  Greet := 'hello, ' + name;
end;

function Noise: integer;
var pad: array[1..32] of integer; i: integer;
begin
  for i := 1 to 32 do pad[i] := 999;
  Noise := 0;
end;

var a, b: string;
    k: integer;
begin
  a := F(1);
  writeln(a);
  writeln(F(1) + F(2));
  writeln(Greet('world'));
  writeln(Greet(F(2)));
  k := Noise;
  writeln(a);
  b := F(2);
  writeln(a, ' ', b);
end.
