{ A function returning a record across a unit boundary. The result buffer is
  caller-allocated and sized from the declaration, which the object has to
  carry: without it the call site emitted a memory.copy with one operand.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program l003;

uses RecU;

var
  p: TP;
begin
  p := Make(3, 4);
  writeln(SumOf(p), ' ', p.x, ',', p.y)
end.
