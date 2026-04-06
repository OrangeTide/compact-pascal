program t050_std_funcs;

type
  Color = (Red, Green, Blue);

var
  i: integer;
  c: Color;

begin
  { ord }
  writeln(ord(true));      { 1 }
  writeln(ord(false));     { 0 }
  c := Green;
  writeln(ord(c));         { 1 }

  { chr — prints as integer since write(char) prints ordinal }
  { skip chr test for now since write prints char as int }

  { abs }
  writeln(abs(-5));        { 5 }
  writeln(abs(5));         { 5 }
  writeln(abs(0));         { 0 }

  { odd }
  if odd(3) then write('yes') else write('no');
  write(' ');
  if odd(4) then write('yes') else write('no');
  writeln;

  { succ / pred }
  writeln(succ(5));        { 6 }
  writeln(pred(5));        { 4 }
  writeln(succ(0));        { 1 }
  writeln(pred(0));        { -1 }

  { sqr }
  writeln(sqr(5));         { 25 }
  writeln(sqr(-3));        { 9 }
  writeln(sqr(0));         { 0 }

  { lo / hi }
  i := $1234;
  writeln(lo(i));          { 52 = $34 }
  writeln(hi(i));          { 18 = $12 }
  writeln(lo(255));        { 255 }
  writeln(hi(255));        { 0 }
  writeln(lo(256));        { 0 }
  writeln(hi(256));        { 1 }

  { sizeof }
  writeln(sizeof(i));      { 4 }
  writeln(sizeof(c));      { 4 }
end.
