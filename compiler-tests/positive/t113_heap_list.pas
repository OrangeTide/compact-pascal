{ A linked list: the shape that was impossible before a heap existed, since
  every size had to be fixed at compile time.

  new and dispose take their size from the pointer's target type rather than
  from an argument, so a caller cannot get it wrong. dispose also clears the
  pointer, which is not standard Pascal: it turns a use after dispose into a
  nil trap rather than a read of memory that now belongs to something else. }
program t113;
type
  PNode = ^TNode;
  TNode = record
    value: integer;
    next: PNode;
  end;
var head, n, t: PNode;
    i, total: integer;
begin
  head := nil;
  for i := 5 downto 1 do begin
    new(n);
    n^.value := i;
    n^.next := head;
    head := n;
  end;

  total := 0;
  n := head;
  while n <> nil do begin
    write(n^.value, ' ');
    total := total + n^.value;
    n := n^.next;
  end;
  writeln;
  writeln('total ', total);

  n := head;
  while n <> nil do begin
    t := n^.next;
    dispose(n);
    n := t;
  end;
  writeln('n is nil after dispose: ', n = nil);
end.
