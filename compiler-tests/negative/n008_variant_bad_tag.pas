program n008_variant_bad_tag;
type
  TData = record
    case kind: integer of
      1: (intVal: integer);
      2: (strVal: string[10])
  end;
const
  data: TData = (kind: 1; strVal: 'wrong');
begin
  writeln(data.kind)
end.
