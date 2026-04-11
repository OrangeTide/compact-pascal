program t045_const_basic;

const
  MaxSize = 100;
  MinSize = 10;
  Range = MaxSize - MinSize;
  Doubled = MaxSize * 2;
  Half = MaxSize div 2;
  NegVal = -42;
  Flags = $FF and $0F;
  Bits = $01 or $F0;
  IsEqual = ord(MaxSize = 100);
  Letter = ord('A');
  Sqr9 = sqr(9);
  Abs42 = abs(-42);
  LoVal = lo($1234);
  HiVal = hi($1234);

var
  x: integer;

begin
  writeln(MaxSize);       { 100 }
  writeln(Range);         { 90 }
  writeln(Flags);         { 15 }
  writeln(Bits);          { 241 }
  writeln(IsEqual);       { 1 }
  writeln(Letter);        { 65 }
  writeln(Sqr9);          { 81 }
  writeln(Abs42);         { 42 }
  writeln(LoVal);         { 52 }
  writeln(HiVal);         { 18 }
  x := MaxSize + 5;
  writeln(x);             { 105 }
end.
