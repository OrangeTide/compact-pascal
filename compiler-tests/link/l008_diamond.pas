{ A diamond: Left and Right both call into Base, and the program imports only
  the two arms. Base is placed because Left and Right need it, not because
  anything mentions it, and its data is aligned when appended so that an i32
  field of an imported record does not land on an odd address.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program l008;

uses Left, Right;

begin
  writeln(L + R)
end.
