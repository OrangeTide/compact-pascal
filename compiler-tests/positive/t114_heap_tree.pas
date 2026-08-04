{ A binary tree built through var parameters, walked, and freed recursively.

  `Ins(t^.left, v)` is why the var-argument path had to learn ^ and .field:
  it previously accepted only [index], which was enough while no designator
  could reach through a pointer.

  The loop at the end allocates and frees the same block two thousand times.
  Without reuse the heap would climb and eventually meet the stack; the count
  is high enough that a leak of one block per iteration would not fit. }
program t114;
type
  PN = ^TN;
  TN = record
    v: integer;
    l, r: PN;
  end;
var root, p: PN;
    i: integer;

procedure Ins(var t: PN; v: integer);
begin
  if t = nil then begin
    new(t);
    t^.v := v;
    t^.l := nil;
    t^.r := nil;
  end
  else if v < t^.v then Ins(t^.l, v)
  else Ins(t^.r, v);
end;

procedure Walk(t: PN);
begin
  if t <> nil then begin
    Walk(t^.l);
    write(t^.v, ' ');
    Walk(t^.r);
  end;
end;

procedure FreeAll(var t: PN);
begin
  if t <> nil then begin
    FreeAll(t^.l);
    FreeAll(t^.r);
    dispose(t);
  end;
end;

begin
  root := nil;
  Ins(root, 5); Ins(root, 3); Ins(root, 8);
  Ins(root, 1); Ins(root, 4); Ins(root, 7); Ins(root, 9);
  Walk(root);
  writeln;
  FreeAll(root);
  writeln('root is nil: ', root = nil);

  for i := 1 to 2000 do begin
    new(p);
    p^.v := i;
    dispose(p);
  end;
  writeln('reused');
end.
