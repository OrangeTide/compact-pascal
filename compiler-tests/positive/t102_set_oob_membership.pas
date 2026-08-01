{ An ordinal outside a set's representation must test false. WASM masks a
  shift count to five bits, so a small set once reported "99 in [1,3]" as
  true because 99 aliased to bit 3. A large set indexed past its storage
  read adjacent memory instead. Negatives must be false too. }
program t102;
type Small = set of 0..7;
     Big   = set of 0..255;
var s: Small; b: Big; i: integer;
begin
  s := [1,3];
  write('small in-range: ');
  for i := 0 to 4 do write(ord(i in s));
  writeln;
  write('small aliases (32,35,99,-1): ');
  i := 32;  write(ord(i in s));
  i := 35;  write(ord(i in s));
  i := 99;  write(ord(i in s));
  i := -1;  write(ord(i in s));
  writeln;
  b := [1,3,200];
  write('large in-range (1,3,200,2): ');
  i := 1;   write(ord(i in b));
  i := 3;   write(ord(i in b));
  i := 200; write(ord(i in b));
  i := 2;   write(ord(i in b));
  writeln;
  write('large out-of-range (256,300,-1): ');
  i := 256; write(ord(i in b));
  i := 300; write(ord(i in b));
  i := -1;  write(ord(i in b));
  writeln;
end.
