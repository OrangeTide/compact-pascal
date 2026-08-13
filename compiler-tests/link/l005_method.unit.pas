unit MethU;
interface
type TR = record w: integer end;
function Area for (r: TR): integer;
function MakeR(v: integer): TR;
implementation
function Area for (r: TR): integer; begin Area := r.w * 2 end;
function MakeR(v: integer): TR; var t: TR; begin t.w := v; MakeR := t end;
end.
