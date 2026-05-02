program t099_variant_record_typed_const;
type
  TData = record
    case kind: integer of
      1: (intVal: integer);
      2: (strVal: string[10])
  end;
const
  data1: TData = (kind: 1; intVal: 42);
  data2: TData = (kind: 2; strVal: 'hello');
begin
  writeln(data1.kind);
  writeln(data1.intVal);
  writeln(data2.kind);
  writeln(data2.strVal)
end.
