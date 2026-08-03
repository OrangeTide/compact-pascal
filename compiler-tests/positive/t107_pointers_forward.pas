{ A pointer type may name a type declared later in the same type block.
  This is the one break from declare-before-use the language allows, and
  without it a linked node type cannot be written at all: the record needs
  the pointer type, and the pointer type needs the record.
  The nodes here are ordinary variables, so no heap is required. }
program t107;
type
  PNode = ^TNode;
  TNode = record
    value: integer;
    next: PNode;
  end;
var
  a, b, c: TNode;
  walk: PNode;
  total: integer;

procedure Bump(p: PNode; by: integer);
begin
  p^.value := p^.value + by;
end;

function SumFrom(start: PNode): integer;
var s: integer; n: PNode;
begin
  s := 0;
  n := start;
  while n <> nil do begin
    s := s + n^.value;
    n := n^.next;
  end;
  SumFrom := s;
end;

begin
  a.value := 1; a.next := @b;
  b.value := 2; b.next := @c;
  c.value := 3; c.next := nil;

  walk := @a;
  total := 0;
  while walk <> nil do begin
    total := total + walk^.value;
    walk := walk^.next;
  end;
  writeln('total ', total);

  Bump(@b, 10);
  writeln('sum ', SumFrom(@a));
end.
