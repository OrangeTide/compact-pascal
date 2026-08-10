{ Writing a file, closing it, reopening the same text variable for reading,
  and reading from it used to append a second copy of the data at the close.
  The flush wrote whatever TextOfsLen held, and the read path uses that same
  field for the bytes it has buffered.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program t132;
uses Files;
var
  f: text;
  i, n: integer;
  c: char;
begin
  Assign(f, 'roundtrip.dat');
  Rewrite(f);
  for i := 0 to 255 do
    Write(f, chr(i));
  Close(f);

  Assign(f, 'roundtrip.dat');
  Reset(f);
  n := 0;
  while not Eof(f) do begin
    Read(f, c);
    if ord(c) <> n mod 256 then
      writeln('byte ', n, ' is wrong');
    n := n + 1
  end;
  Close(f);
  writeln('read back ', n, ' bytes')
end.
