# IP Pascal / Pascaline

**Author:** Scott A. Moore
**First released:** ~1993–2008 (extensions accumulated over this period)
**Implementation:** IP portability platform (cross-platform widget toolkit, TCP/IP, MIDI)
**Website:** https://www.moorecad.com/ippas/ (archived)
**Wikipedia:** https://en.wikipedia.org/wiki/IP_Pascal

## Core Concept

IP Pascal implements **Pascaline** (named after Blaise Pascal's calculator), a highly
extended superset of ISO 7185 Pascal. The design philosophy is to extend Pascal with
modern features — modules, objects, concurrency, dynamic arrays — while *never* reducing
type safety. Moore positions Pascaline as comparable to C# in functionality but rooted
in Pascal's stronger type discipline: "the functionality of the language is similar to
that of C#, which implements a C++ like language but with the type insecurities removed."

IP Pascal passed the Pascal Validation Suite, making it one of the few extended Pascals
that remain fully ISO 7185 compliant at the base level.

## Features of Interest

### Module System (uses, joins, share)

Pascaline has a rich module system with five module kinds:

| Kind        | Has init | Has exit | Has data | Thread  | Purpose |
|-------------|----------|----------|----------|---------|---------|
| `module`    | yes      | yes      | yes      | caller  | General module with initialization and cleanup |
| `program`   | yes      | no       | yes      | main    | Entry point; runs init to completion |
| `process`   | yes      | no       | yes      | own     | Spawns a separate thread |
| `monitor`   | yes      | yes      | yes      | locked  | Thread-safe data; auto-mutex on entry procedures |
| `share`     | yes      | yes      | no       | any     | Stateless library code; callable by any module |

Modules must occupy a single file and bear the same name as their file.

**`uses`** merges the referenced module's namespace into the referencing module; name
conflicts are an error. **`joins`** makes the module accessible but keeps namespaces
separate — access via qualified identifiers (`module.identifier`). This is a clean
two-tier visibility model.

Declarations inside modules form their own interface specification — no separate
interface/implementation split is required. A "skeleton" (interface-only) file can be
derived by stripping code, but it's optional.

### Daisy-Chained Programs

All modules in a system are "daisy chained" — each executes its initialization section
in order. A `program` module simply doesn't return from its init section until its work
is done. Multiple `program` sections execute in sequence. This is an elegant model for
composing cooperating programs.

### Dynamic Arrays

Dynamic arrays are "containers" for static arrays. A static array can be passed to a
dynamic array parameter, or a dynamic array can be allocated with `new`. The `max`
function returns the upper bound. This makes dynamic and static arrays fully
interchangeable — unique among Pascal implementations.

```pascal
type string = packed array of char;
var s: string;
begin
  new(s, 12);
  s := 'Hello, world';
end.
```

### `view` Parameters

Pascaline adds `view` and `out` parameter modes. A `view` parameter has value semantics
(callee cannot modify the original) but is passed efficiently (likely by reference
internally). It's essentially a read-only reference parameter — similar to `const` in
later Pascal dialects but with clearer semantics.

```pascal
procedure wrtstr(view s: string);
```

### Constant Expressions

Constants can reference other constants in expressions:

```pascal
const b = a + 10;
```

This is a straightforward but useful extension that standard Pascal lacks.

### Underscores in Numbers

The `_` character can appear anywhere in a number except the first digit, serving as a
visual separator:

```pascal
a := 1234_5678;
```

### Radix Literals

Three prefix forms: `$ff` (hex), `&76` (octal), `%011000` (binary).

### Forward Syntax (Header Duplication)

Forward-declared procedures repeat the full header at the definition:

```pascal
procedure x(i: integer); forward;
...
procedure x(i: integer);
begin ... end;
```

This makes it easier to use cut-and-paste for forwards and keeps parameter lists visible
at the definition site.

### `fixed` Declarations

Structured constant initializers for arrays and records:

```pascal
fixed table: array [1..5] of record
    a: integer; packed array [1..10] of char
  end =
  array
    record 1, 'data1     ' end,
    record 2, 'data2     ' end,
    record 3, 'data3     ' end
  end;
```

This is a typed constant initializer with full structural nesting — more capable than
Turbo Pascal's typed constants for complex data.

### Boolean Bit Operations

`and`, `or`, `not`, `xor` work on integer operands as bitwise operators:

```pascal
a := a and b;
b := b or $a5;
a := not b;
b := a xor b;
```

### Monitors and Semaphores

The `monitor` module kind provides automatic mutual exclusion on all externally
accessible procedures. Semaphores (`wait`, `signalone`) enable task event queuing within
monitors, following Brinch Hansen's classical methods.

```pascal
monitor test;
var notempty, notfull: semaphore;
procedure enterqueue;
begin
  while nodata do wait(notempty);
  ...
  signalone(notfull)
end;
```

### Overloads and Overrides

**Overloads** group procedures/functions under the same name, distinguished by parameter
signature. Ambiguous overloads are rejected at declaration time — no priority rules.

**Overrides** hook procedures in other modules. The overriding module can call the
original via `inherited`:

```pascal
override procedure x;
begin
  inherited x
end;
```

### Objects

Classes with single inheritance (`extends`), reference types, virtual methods,
`is` type testing:

```pascal
class alpha;
extends beta;
type alpha_ref = reference to alpha;
var a, b: integer;
virtual procedure x(d: integer);
begin ... end;
```

### Extended Range Variables

Types beyond `integer` range: `linteger` (double-range), `cardinal` (unsigned),
`lcardinal` (unsigned double-range), with corresponding limits `maxlint`, `maxcrd`,
`maxlcrd`.

### Other Minor Extensions

- Alphanumeric goto labels
- String escape sequences using ISO 8859-1 mnemonics (`\cr\lf`)
- `halt` procedure
- `command` pseudo-file for reading command-line arguments
- Automatic program header file to command-line argument binding
- File operations: `assign`, `update`, `position`, `length`, `location`, `close`
- Relaxed declaration order (label, const, type, var, fixed can appear in any order)

## References

- Wikipedia: https://en.wikipedia.org/wiki/IP_Pascal
- Pascaline language description: https://standardpascal.org/pascaline.htm
- IP Pascal homepage (archived): https://web.archive.org/web/20210321211350/http://www.moorecad.com/ippas/
- Pascal-P6 (open-source Pascaline implementation): https://github.com/samiam95124/Pascal-P6/
