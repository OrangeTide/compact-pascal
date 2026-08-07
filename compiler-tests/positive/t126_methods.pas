{ Standalone methods: value and pointer receivers, extra parameters, calls in
  statements and in expressions, and automatic dereference.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
program t126;
type
  TRect = record
    W, H: integer;
  end;
  TCat = record
    Name: string[20];
    Purrs: integer;
  end;

function Area for (r: TRect): integer;
begin
  Area := r.W * r.H
end;

function Scaled for (r: TRect) (k: integer): integer;
begin
  Scaled := r.W * r.H * k
end;

function Tag for (r: TRect): string;
begin
  Tag := 'rect'
end;

procedure Grow for (r: ^TRect) (k: integer);
begin
  r^.W := r^.W * k;
  r^.H := r^.H * k
end;

procedure Bump for (r: TRect);
begin
  { A value receiver is a copy, so this cannot reach the caller's record. }
  r.W := r.W + 100
end;

procedure Purr for (c: ^TCat);
begin
  c^.Purrs := c^.Purrs + 1;
  writeln(c^.Name, ' purrs (', c^.Purrs, ')')
end;

procedure Rename for (c: ^TCat) (const NewName: string);
begin
  c^.Name := NewName
end;

var
  q: TRect;
  p: ^TRect;
  MyCat: TCat;
begin
  q.W := 3;
  q.H := 4;
  writeln(q.Area);
  writeln(q.Scaled(2));
  writeln(q.Area + q.Area);
  writeln(q.Tag, ' area ', q.Area);

  q.Bump;
  writeln(q.Area);

  q.Grow(10);
  writeln(q.Area);

  { A pointer designator is dereferenced automatically, so p.Area and
    p^.Area mean the same. }
  p := @q;
  writeln(p.Area);
  writeln(p^.Area);
  p.Grow(2);
  writeln(p.Area);

  MyCat.Name := 'Tom';
  MyCat.Purrs := 0;
  MyCat.Purr;
  MyCat.Rename('Whiskers');
  MyCat.Purr
end.
