unit RecU;
interface
type TP = record x, y: integer end;
function Make(a, b: integer): TP;
function SumOf(const p: TP): integer;
implementation
function Make(a, b: integer): TP;
var t: TP;
begin t.x := a; t.y := b; Make := t end;
function SumOf(const p: TP): integer;
begin SumOf := p.x + p.y end;
end.
