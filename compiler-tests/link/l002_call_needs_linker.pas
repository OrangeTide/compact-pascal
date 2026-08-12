{ Calling into a unit leaves placeholder indices in the code. A module
  carrying those would fail validation with nothing to point at, so the
  compiler refuses to write one until the linker exists.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program l002;

uses Geometry;

begin
  writeln(Distance(3, 4))
end.
