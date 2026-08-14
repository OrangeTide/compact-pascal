unit Left;
interface
function L: integer;
implementation
uses Base;
function L: integer; begin Say('from left'); L := Two * 10 end;
end.
