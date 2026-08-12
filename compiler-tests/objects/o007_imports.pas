{ A unit that uses Files needs host functions, and the object has to say
  which. Without them a linker resolves the unit's calls to whatever occupies
  those indices in the merged module.
  Made by a machine. PUBLIC DOMAIN (CC0-1.0) }
unit U; interface
uses Files;
procedure P;
implementation
procedure P; var f: text; begin Assign(f,'x'); end;
end.
