# Vector Pascal

**Designer:** Paul Cockshott
**Affiliation:** Imaging Faraday Partnership, Dept Computing Science, University of Glasgow
**Published:** ACM SIGPLAN Notices, V. 37(6) June 2002
**Target:** SIMD instruction sets (MMX, SSE, AltiVec)
**Source:** Vector Pascal Reference manual PDF (https://dl.acm.org/doi/10.1145/571727.571737)
**Language manual:** https://www.dcs.gla.ac.uk/~wpc/reports/compilers/compilerindex/vp-ver2.html
**Compiler index:** https://www.dcs.gla.ac.uk/~wpc/reports/compilers/compilerindex/x25.html
**Implementation:** Java (open source, available on SourceForge)
**Dependencies:** Java, GCC (djgpp on Windows), NASM assembler, LaTeX (for literate programming)

## Core Concept

Vector Pascal extends Pascal with **array programming abstractions derived from APL**,
designed for efficient use of SIMD (Single Instruction Multiple Data) hardware. The key
idea: all operators are automatically extended to work element-wise on arrays (vectors),
and the compiler maps these operations to hardware SIMD instructions. This brings
APL-style expressiveness to Pascal while generating code that runs 12x faster than
scalar equivalents on MMX.

**Why Pascal over C or Java?** C was rejected because notations like `x+y` for `x` and `y`
declared as `int x[4],y[4]` already mean adding the addresses. Java was rejected
because its JIT code generator made it difficult to efficiently emit SIMD instructions.

## Type System Extensions

### Standard Types

The full set of standard types (from Table 3.2):

| Type | Category | Notes |
|------|----------|-------|
| real | floating point | IEEE 32-bit (chosen because 32-bit SIMD is well supported) |
| double | floating point | IEEE 64-bit |
| byte | integral | 0..255 |
| pixel | fixed point | -1.0..1.0 as signed 8-bit fraction |
| shortint | integral | -128..127 |
| word | integral | 0..65535 |
| integer | integral | -maxint..+maxint |
| cardinal | integral | 0..4292967295 (32-bit unsigned) |
| longint | integral | 32-bit, retained for TP compatibility |
| int64 | integral | 64-bit integer |
| boolean | scalar | false < true |
| char | scalar | chr(0)..charmax |
| complex | composite | record with real and imaginary parts, held to 32-bit precision |

### Vector Types

Arrays of type T are denoted `T[]`. Standard operators automatically extend to work
pointwise:

```pascal
var x, y, k: array [...] of integer;
k := x + y;  { element-wise addition }
```

The **rank** of an array is its number of dimensions. Scalar types have rank 0. When a
lower-rank value appears in an array context, it is **replicated** to fill the array shape.
This is how scalar-to-array broadcasting works:

```pascal
r1:= /2;       { assigns 0.5 to every element — unary / inserts identity 1.0 }
r2:= r1*3;     { multiplies every element by 3 — scalar 3 is replicated }
```

### Pixel Type

Rather than 8-bit unsigned integers (0–255), pixels are conceptualized as **real
numbers in the range -1.0 to 1.0**, implemented as 8-bit signed fixed-point fractions.
This avoids wraparound errors in arithmetic and enables **saturating assignment** that
clips values to the valid range. Performance gains for pixel operations are exceptional
(16x speedup) because explicit bounds checking is eliminated.

The implementation model is 8-bit signed integers treated as fixed-point binary
fractions. Conversions to preserve monotonicity of addition, range of multiplication,
etc. are delegated to the code generator, which uses saturating SIMD instructions where
available.

Mixed-type arithmetic between pixels and other numeric types: both operands are
converted to reals first, the arithmetic is performed, and then if assigned back to a pixel
variable, values >1.0 are clipped to 1.0 and values < -1.0 are clipped to -1.0.

Conversion builtins: `pixel2byte` (maps -1.0..1.0 to 0..255) and `byte2pixel` (reverse).

### Dimensional Types

Type-checked dimensional analysis like physics notation:

```pascal
kms = (mass, distance, time);
meter = real of distance;
second = real of time;
newton = real of mass * distance * time POW -2;
meterpersecond = real of distance * time POW -1;
```

Grammar: `<dimensioned type> ::= <real type> <dimension> ['*' <dimension>]*`
where `<dimension> ::= <identifier> ['POW' [<sign>] <unsigned integer>]`.

The identifier must be a member of a scalar (enum) type, which becomes the **basis
space**. Each dimension carries an integer exponent (the "power"). Dimension deduction
rules use logarithmic addition/subtraction of exponents for `*` and `/`, and require
matching dimensions for `+` and `-`. `POW` between a dimensioned type and an integer
multiplies all exponents.

## Data Parallelism Operations

### Maps (Whole-Array Operations)

Operators and functions automatically extend to arrays:

```pascal
r1 := 1/2;         { assigns 0.5 to each element }
r2 := r1 * 3;      { multiplies every element by 3 }
```

### Array Slicing

Subrange selections from arrays:

```pascal
dataset[i..i+2] := blank;
twoDdata[2..3, 5..6] := twoDdata[4..5, 11..12] * 0.5;
```

The type of `a[i..j]` where `a: array[p..q] of t` is `array[0..j-i] of t`.

### Conditional Operations (SIMD Masking)

`if-then-else` as an expression operates as a map on arrays with boolean mask
evaluation:

```pascal
a := if a > 0 then a else -a    { element-wise abs }
```

Parallelizable expressions evaluate all branches and merge under masking; expressions
with function calls serialize to explicit loops.

### Reductions

Any dyadic operator can become a monadic reduction operator. The `\` (backslash)
notation is used in the paper, but the actual syntax is the operator applied as a unary
prefix. Reduction always operates along the **last** array dimension. An argument of
rank *r* produces a result of rank *r-1* (rank 0 returns the identity).

```pascal
x := +(y * z);    { dot product: sum of element-wise products }
r1 := +r2;        { sum rows of r2 }
```

The reserved word `rdu` is a lexical alternative to `\`, so `+` is equivalent to `rdu+`.

Identity elements by type:

| Type | Operators | Identity |
|------|-----------|----------|
| number | +, - | 0 |
| string | + | "" |
| set | + | empty set |
| set | -, * | full set |
| number | *, /, div, mod | 1 |
| number | max | lowest representable |
| number | min | highest representable |
| boolean | and | true |
| boolean | or | false |

### Iota (Index Generation)

`iota i` returns the i-th implicit loop index, enabling index-based expressions:

```pascal
m := iota 0 + 2 * iota 1
```

### Permutation and Transposition

`perm` performs a generalized permutation of implicit indices. The index-sels are
compile-time integers specifying a permutation:

```pascal
perm [ index-sel [, index-sel]* ] expression
```

In context `perm [i, j, k] e`: `iota 0 = iota i`, `iota 1 = iota j`, `iota 2 = iota k`.
Useful for converting between image formats (e.g. interleaved RGBRGB... vs. planar):

```pascal
screen := perm[2,0,1] img;   { reorder channel/row/col dimensions }
```

`trans` is shorthand for `perm[1,0]` (transpose/cyclic rotation of dimensions).
`diag` is shorthand for `perm[0,0]` (diagonal extraction).

## Operator System

### Automatic Extension

Dyadic operators (+, -, *, /, <, >, =, etc.) work pointwise on arrays. Unary operators
are defined via identity element insertion: `/2` becomes `1/2`, `-a` becomes `0-a`.

### Operator Overloading

New types define operators by specifying:
1. Operator symbol
2. Implementation function (semantic function)
3. Identity element

```pascal
type complex = record data: array[0..1] of real; end;
var complexzero, complexone: complex;

function cmplx(realpart, imag: real): complex;
function complex_add(A, B: Complex): complex;
function complex_multiply(A, B: Complex): complex;
{ ... }

{ Standard operators on complex numbers }
operator + = complex_add, complexzero;
operator / = complex_divide, complexone;
operator * = complex_multiply, complexone;
operator - = complex_subtract, complexzero;
```

The compiler resolves predefined operators first, then searches user-defined overloads.
The identity element ensures that unary operators and reductions work correctly:
unary `-x` for complex becomes `complexzero - x`, and `1/x` becomes
`complexone / x`. Overloaded operators can be used in array maps and reductions.

### Virtual Array Variables

If an array variable occurs on the right side of an assignment, it can be indexed by
another array. If `x:array[t0]` of `t1` and `y:array[t1]` of `t2`, then `y[x]` denotes a
virtual array of `t2` such that `y[x][i] = y[x[i]]`. Useful for performing permutations:

```pascal
const perm: array[0..3] of integer = (3,1,2,0);
var ma, m0: array[0..3] of integer;
ma := m0[perm];   { reorders m0 by perm indices }
```

### Dynamic Arrays (Schematic/Parameterized Types)

Pointer types can point to dynamic arrays whose bounds are determined at runtime.
Uses Pascal 90's schematic types:

```pascal
type z(a, b: r) = array[a..b] of t;
if p: z then new(p, n, m)   { allocates array with bounds n..m }
```

Bounds accessed as `p.a`, `p.b`. Vector Pascal supports dynamic but not static
parameterized types.

## Compilation and Code Generation

Vector Pascal compiles through **ILCG** (Intermediate Language for Code Generation), a
strongly-typed abstract semantic tree implemented as a Java data structure. Machine-
specific code generators use pattern-matching to select SIMD instructions.

Code generators exist for:
- Intel 486 (scalar fallback)
- Pentium with MMX
- Pentium III (SSE, P3)
- Pentium 4 (P4)
- AMD K6
- AMD Athlon
- AMD Opteron 64-bit (with multi-core parallelism support)
- Sony PlayStation 2 Emotion Engine
- Cell processor (PS3) — prototype

For arrays longer than the native SIMD width, the system generates loops over
SIMD-width chunks.

### Dual Compilation of Conditional Expressions

The `if-then-else` expression has two compilation strategies:

1. **Parallelizable** (no function calls): condition and both arms are evaluated, then
   merged under a boolean mask. `a := if a>0 then a else -a` becomes
   `a := (a and (a > 0)) or (not (a > 0) and -a)`.
2. **Non-parallelizable** (contains function calls): translated to a standard scalar
   `for` loop with `if` statement.

This dual strategy allows the same language construct to be used for both recursive
function definitions and parallel data selection.

## Performance

| Data Type | Speedup vs. Scalar |
|-----------|--------------------|
| Byte (pixel) operations | 7–16x |
| 16-bit integers | ~4x |
| 32-bit integers/reals | 0.3–0.6x relative gain |

Saturated pixel arithmetic shows the best gains (16x) because SIMD saturating
instructions replace scalar code with explicit bounds checks.

## Programs and Units

Vector Pascal uses Turbo Pascal-style separate compilation units. A compilation unit
can be a **program**, **unit**, or **library**.

- `library` keyword (instead of `program` or `unit`) makes interface procedure/function
  declarations accessible to routines written in other languages (FFI export).
- Units have `interface` and `implementation` sections; function/procedure headings
  in the interface can omit the body if redeclared in implementation.
- Unit invocation order: uses list left to right, depth-first, each unit invoked at most
  once.
- Units in the interface section of other units form enclosing scopes — rightmost in
  the uses list has highest priority.
- A **System Unit** provides pre-declared identifiers (like `maxint`, `pi`, `complexzero`).

## Reserved Words (Complete List)

ABS, ADDR, AND, ARRAY, BEGIN, BYTE2PIXEL, CHR, CASE, CDECL, CONST, COS,
DISPOSE, DIV, DO, DOWNTO, END, ELSE, EXIT, EXTERNAL, FALSE, FILE, FOR,
FUNCTION, GOTO, IF, IMPLEMENTATION, IN, INTERFACE, IOTA, LABEL, LIBRARY,
LN, MAX, MIN, MOD, NAME, NDX, NEW, NOT, OF, OR, ORD, PACKED, PERM,
PIXEL2BYTE, POW, PRED, PROCEDURE, PROGRAM, RDU, READ, READLN, RECORD,
REPEAT, ROUND, SET, SHL, SHR, SIN, SIZEOF, SQRT, STRING, SUCC, TAN, THEN,
TO, TRANS, TRUE, TYPE, UNIT, UNTIL, USES, VAR, WITH, WHILE, WRITE, WRITELN.

Notable additions beyond standard Pascal: IOTA, NDX, PERM, TRANS, RDU, POW,
PIXEL2BYTE, BYTE2PIXEL, LIBRARY, EXTERNAL, NAME, CDECL, SHL, SHR.

## Lexical Details

- Case insensitive identifiers. Underscore `_` is significant in identifiers.
- Hex literals: `$01`, `$3ff`, `$5A` ($ prefix).
- Based integers: `2#1101` (binary), `8#67` (octal), `20#7i` (base 20).
- Comments: `{ }` or `(* *)`. Comment starting with `{` must end with `}`;
  comment starting with `(*` must end with `*)`.
- Exponentiation: `x pow y` (integer exponent, result type of x) or `x ** y`
  (real exponent, always real result).
- `exit` statement: bare `exit;` returns from procedure; `exit(expr)` returns value
  from function.

## IDE: VIPER

Vector Pascal includes the VIPER IDE providing:
- Syntax highlighting
- Project management
- Compilation and linking integration
- VPTeX: automatic Pascal-to-LaTeX translation for literate programming via
  comment-embedded LaTeX markup

## Significance

Vector Pascal demonstrates that a Pascal-family language can express data-parallel
algorithms naturally and map them efficiently to SIMD hardware. The APL-derived
abstractions (maps, reductions, iota, slicing) are the key insight — they provide a
level of abstraction above raw SIMD intrinsics while still generating efficient code.

The dimensional type system is independently interesting as a compile-time safety
mechanism for scientific computing.

The unary-operator-via-identity-element design is elegant: defining just an identity
element and a binary function gives you unary operators, reductions, and array
broadcasting for free. The operator overloading system builds on this — user-defined
types get the full array algebra just by providing the three pieces (symbol, function,
identity).

## References

- P. Cockshott, "Vector Pascal, an Array Language," *ACM SIGPLAN Notices*, vol. 37,
  no. 6, pp. 59–69, 2002. https://dl.acm.org/doi/10.1145/571727.571737
- P. Cockshott and K. Renfrew, *SIMD Programming Manual for Linux and Windows*,
  Springer, 2004.
- Vector Pascal language manual:
  https://www.dcs.gla.ac.uk/~wpc/reports/compilers/compilerindex/vp-ver2.html
- Paul Cockshott's publications: http://paulcockshott.co.uk/computerscience/
