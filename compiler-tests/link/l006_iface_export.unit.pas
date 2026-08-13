unit IU;
interface
type
  IPet = interface Legs: function: integer; end;
  TCat = record n: integer end;
function MakeCat: TCat;
implementation
implement IPet for TCat;
  function Legs: integer; begin Legs := 4 end;
end;
function MakeCat: TCat; var c: TCat; begin c.n := 1; MakeCat := c end;
end.
