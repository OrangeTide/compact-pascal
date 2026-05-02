program n009_variant_unnamed_tag;
type
  TData = record
    case integer of
      1: (intVal: integer);
      2: (strVal: string[10])
  end;
const
  data: TData = (intVal: 42);
begin
  writeln(data.intVal)
end.
