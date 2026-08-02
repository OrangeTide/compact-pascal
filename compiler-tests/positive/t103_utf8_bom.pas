{ A UTF-8 byte order mark is valid UTF-8 and Windows editors write one
  by default. Rejecting it turned an ordinary save into "unexpected
  character" on line 1. This file begins with a real BOM; do not strip it. }
program t103;
begin
  writeln('bom handled');
end.
