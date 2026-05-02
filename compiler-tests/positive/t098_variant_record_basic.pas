program t098_variant_record_basic;
type
  TShape = record
    case shapeType: integer of
      1: (radius: integer);
      2: (width: integer; height: integer)
  end;
var
  s1: TShape;
  s2: TShape;
begin
  s1.shapeType := 1;
  s1.radius := 10;
  writeln(s1.shapeType);
  writeln(s1.radius);

  s2.shapeType := 2;
  s2.width := 20;
  s2.height := 30;
  writeln(s2.shapeType);
  writeln(s2.width);
  writeln(s2.height)
end.
