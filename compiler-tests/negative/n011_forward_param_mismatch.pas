{ The reference requires a forward declaration's header to be repeated in
  full at the definition. A differing parameter count once emitted a module
  that failed WASM validation, so the error arrived from the runtime rather
  than the compiler. }
program n011;
procedure Q(a: integer); forward;
procedure Q(a, b: integer);
begin
  writeln(a, b);
end;
begin
  Q(1, 2);
end.
