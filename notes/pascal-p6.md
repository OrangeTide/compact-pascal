# Pascal-P6 (Pascaline)

**Author:** Scott A. Moore
**Lineage:** Pascal-P2 → P4 → P5 (ISO 7185) → P6 (Pascaline)
**Implementation:** Self-compiling compiler (pcom), P-code interpreter (pint), AMD64 native code generator (pgen)
**Repository:** https://github.com/samiam95124/Pascal-P6
**Language spec:** https://standardpascal.org/pascaline.htm

## Core Concept

Pascal-P6 is the sixth iteration of Wirth's original Pascal-P compiler system, upgraded
to implement the **Pascaline** language — the same language as IP Pascal but in an
open-source, portable P-machine implementation. The design goal is to demonstrate that
Pascal can be extended to modern language functionality (modules, objects, exceptions,
dynamic arrays, operator overloading) while maintaining **full backward compatibility
with ISO 7185** and **never breaking type safety**.

Pascal-P6 is both a language implementation and a historical artifact: it continues the
Pascal-P tradition that seeded UCSD Pascal and (indirectly) Borland Pascal.

## Historical Significance

The Pascal-P lineage:

- **Pascal-P2** (1970s): The clean reference version that became the foundation for
  UCSD Pascal, which led to Borland/Turbo Pascal.
- **Pascal-P4**: Improved iteration from the Zurich group.
- **Pascal-P5**: Fully ISO 7185 compliant version by Scott Moore.
- **Pascal-P6**: Pascaline extensions added to P5.

## Features

Pascal-P6 implements all the Pascaline features documented in the IP Pascal notes
(modules, monitors, dynamic arrays, objects, overloads, overrides, `view` parameters,
`fixed` declarations, etc.). Additionally:

### Self-Compiling

All components — compiler (pcom), interpreter (pint), code generator (pgen), and build
tool (pc) — are written in Pascaline and compile with P6 itself. There are "considerable
support sections in C" using C89. This makes P6 a practical example of a self-hosting
Pascal system.

### AMD64 Native Code Generation

Beyond the traditional P-code interpreter, P6 includes a native AMD64 code generator,
making it potentially usable for production work on Linux x86-64.

### Exception Handling

Pascaline adds `try`/`except`/`else`:

```pascal
try
  { guarded statements }
except
  { exception handler }
else
  { executed on normal termination }
end;
```

The `else` clause for normal termination is unusual — most exception systems only have
try/catch/finally.

### Operator Overloading

User-defined operators for custom types. Details follow the module and object system.

### Dynamic Arrays

Extends array handling to cover dynamically created arrays (including `array of char`),
fully compatible with ISO 7185 static arrays. The `max` function returns the dynamic
upper bound.

### Current Status

Pascal-P6 is under active development. The Pascaline language spec is expected to reach
version 1.0 when the P6 implementation is complete and tested. Currently limited to
Linux (Ubuntu tested).

## References

- GitHub repository: https://github.com/samiam95124/Pascal-P6
- Documentation: https://samiam95124.github.io/Pascal-P6/
- Pascaline language description: https://standardpascal.org/pascaline.htm
- Hans Otten's page: http://pascal.hansotten.com/px-descendants/p6-pascal/
