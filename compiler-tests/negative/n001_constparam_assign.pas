program n001_constparam_assign;

procedure Foo(const x: integer);
begin
  x := 10;
end;

begin
  Foo(5);
end.
