# Vector Pascal

**Designer:** Paul Cockshott
**Affiliation:** University of Glasgow
**Released:** ~2002
**Target:** SIMD instruction sets (MMX, SSE, AltiVec)
**Wikipedia:** (see references)
**Language manual:** https://www.dcs.gla.ac.uk/~wpc/reports/compilers/compilerindex/vp-ver2.html

## Core Concept

Vector Pascal extends Pascal with **array programming abstractions derived from APL**,
designed for efficient use of SIMD (Single Instruction Multiple Data) hardware. The key
idea: all operators are automatically extended to work element-wise on arrays (vectors),
and the compiler maps these operations to hardware SIMD instructions. This brings
APL-style expressiveness to Pascal while generating code that runs 12x faster than
scalar equivalents on MMX.

## Type System Extensions

### Vector Types

Arrays of type T are denoted `T[]`. Standard operators automatically extend to work
pointwise:

```pascal
var x, y, k: array [...] of integer;
k := x + y;  { element-wise addition }
```

### Pixel Type

Rather than 8-bit unsigned integers (0–255), pixels are conceptualized as **real
numbers in the range -1.0 to 1.0**, implemented as 8-bit signed fixed-point fractions.
This avoids wraparound errors in arithmetic and enables **saturating assignment** that
clips values to the valid range. Performance gains for pixel operations are exceptional
(16x speedup) because explicit bounds checking is eliminated.

### Dimensional Types

Type-checked dimensional analysis like physics notation:

```pascal
newton = real of mass * distance * time POW -2
```

Addition/subtraction requires matching dimensions; multiplication/division combines
dimension exponents. This catches unit errors at compile time.

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

The `\` (backslash) prefix collapses arrays along the last dimension:

```pascal
x := +(y * z);    { dot product: sum of element-wise products }
r1 := +r2;        { sum rows of r2 }
```

Identity elements anchor reductions (0 for addition, 1 for multiplication, etc.).

### Iota (Index Generation)

`iota i` returns the i-th implicit loop index, enabling index-based expressions:

```pascal
m := iota 0 + 2 * iota 1
```

### Permutation and Transposition

- `perm[indices]` reorders array dimensions
- `trans` performs cyclic rotation of dimensions
- `diag` extracts diagonal elements

## Operator System

### Automatic Extension

Dyadic operators (+, -, *, /, <, >, =, etc.) work pointwise on arrays. Unary operators
are defined via identity element insertion: `/2` becomes `1/2`, `-a` becomes `0-a`.

### Operator Overloading

New types define operators by specifying:
1. Operator symbol
2. Implementation function
3. Identity element

The compiler resolves predefined operators first, then searches user-defined overloads.

## Compilation and Code Generation

Vector Pascal compiles through **ILCG** (Intermediate Language for Code Generation), a
strongly-typed abstract semantic tree implemented as a Java data structure. Machine-
specific code generators use pattern-matching to select SIMD instructions.

Code generators exist for:
- Intel 486 (scalar fallback)
- Pentium with MMX
- Pentium III (SSE)
- AMD K6

For arrays longer than the native SIMD width, the system generates loops over
SIMD-width chunks.

## Performance

| Data Type | Speedup vs. Scalar |
|-----------|--------------------|
| Byte (pixel) operations | 7–16x |
| 16-bit integers | ~4x |
| 32-bit integers/reals | 0.3–0.6x relative gain |

Saturated pixel arithmetic shows the best gains (16x) because SIMD saturating
instructions replace scalar code with explicit bounds checks.

## Significance

Vector Pascal demonstrates that a Pascal-family language can express data-parallel
algorithms naturally and map them efficiently to SIMD hardware. The APL-derived
abstractions (maps, reductions, iota, slicing) are the key insight — they provide a
level of abstraction above raw SIMD intrinsics while still generating efficient code.

The dimensional type system is independently interesting as a compile-time safety
mechanism for scientific computing.

## References

- P. Cockshott, "Vector Pascal, an Array Language," *ACM SIGPLAN Notices*, vol. 37,
  no. 6, pp. 59–69, 2002. https://dl.acm.org/doi/10.1145/571727.571737
- P. Cockshott and K. Renfrew, *SIMD Programming Manual for Linux and Windows*,
  Springer, 2004.
- Vector Pascal language manual:
  https://www.dcs.gla.ac.uk/~wpc/reports/compilers/compilerindex/vp-ver2.html
- Paul Cockshott's publications: http://paulcockshott.co.uk/computerscience/
