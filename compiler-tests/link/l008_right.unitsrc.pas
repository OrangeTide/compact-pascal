unit Right;
interface
function R: integer;
implementation
uses Base;
function R: integer; begin Say('from right'); R := Two * 100 end;
end.
