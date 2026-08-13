unit ProcU;
interface
type TOp = function(a: integer): integer;
function Dbl(a: integer): integer;
function Pick: TOp;
implementation
function Dbl(a: integer): integer; begin Dbl := a * 2 end;
function Pick: TOp; begin Pick := @Dbl end;
end.
