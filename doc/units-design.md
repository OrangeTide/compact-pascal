# Separately Compiled Units: Design

Status: **proposal, for review.** This is Phase L1 of `PLAN.md`. Nothing here
is implemented. It exists so the design can be argued with before four weeks
of implementation are spent on it.

Made by a machine. PUBLIC DOMAIN (CC0-1.0)

## What has to be true at the end

From the roadmap: *a three-unit program compiles from the command line, each
unit compiled separately, and recompiling one unit does not require
recompiling the others.*

The last clause is the whole difficulty. Without it, "units" are just
`{$I}` with better scoping, which the compiler already has.

## The decision that constrains everything else

A unit has to become WASM somehow. There are two shapes, and the choice
determines the object format, the linker, the initialization story, and
whether the runtime model changes at all.

### Option A: one WASM module per unit

Each unit compiles to a runnable module. Cross-unit calls become WASM imports
and exports, and the host — or a small loader — instantiates the set and wires
them together.

It is attractive because WASM already has the mechanism, and because there is
no linker to write.

**It does not work under this project's constraints, and the reason is
specific.** Units must share the stack pointer, the eight display registers,
and the heap boundary. Those are mutable WASM globals. Importing a mutable
global is not in WASM 1.0; it is the *Import/Export of Mutable Globals*
proposal. Checked rather than recalled:

```
$ wasm-validate --disable-mutable-globals mg.wasm
mg.wasm:000001c: error: mutable globals cannot be imported
```

There are two ways around it and both are worse than a linker:

- **Take the extra proposal.** Cheap to say, but it is a second post-MVP
  dependency taken to avoid work, which is the wrong reason to spend a
  portability budget. See "What the compiler actually requires" below.
- **Move `$sp`, the display, and the heap boundary into linear memory.** Every
  frame entry and exit becomes a load and a store instead of a global access,
  and every upvalue access grows. That is a permanent cost on all code to buy
  a one-time saving on the toolchain.

There is a third problem even if the globals are solved: each module carries
its own data segment, and the addresses are baked in at compile time. Two units
compiled independently would both place their literals at the same addresses.
Fixing that needs a base-relative data model, which is a relocation scheme —
that is, a linker, arrived at by a longer road.

### Option B: compile to objects, link into one module — recommended

Each unit compiles to an intermediate object holding its code, data, and a
table of the places that need patching. A linker merges the objects into a
single WASM module, assigning final function indices and data addresses.

The runtime model does not change at all: one module, one memory, one stack
pointer, one heap. Everything the compiler does today keeps working, and
nothing about the WASM feature set moves.

The cost is an object format and a linker. Both are small because the project
controls both ends: no archives, no shared libraries, no symbol visibility
rules, no ELF.

**Recommendation: Option B.**

## What the compiler actually requires

Worth stating plainly because the documentation was wrong about it until this
design was written, and because Option A's cost turns on it.

The compiler emits WASM 1.0 **plus `memory.copy`**, from the bulk-memory
proposal, used for structured assignment. Every other post-MVP proposal is
unused, and `make check-wasm-features` now asserts exactly that on every
preflight so the claim cannot drift again.

That is the budget: one proposal, accepted by every runtime this project
targets. Checked rather than dated — a module using `memory.copy` runs under
wasmtime and wasmer and validates in Node. Option A would spend a second
proposal to avoid writing a linker.

## The object format

An object is a file, not a WASM module. It is the compiler's own section
buffers plus the information a linker needs to relocate them.

```
magic       "CPO1"
unit name   short string
interface   the interface description, below
types       WASM type section entries, as emitted
imports     WASM imports this unit needs (host functions only)
functions   code bodies, concatenated, with a length per function
data        the data segment bytes
relocations one entry per patch site
```

A relocation is `(offset, kind, symbol)`, where kind is one of:

| Kind | Patches | Why it is needed |
|---|---|---|
| `func` | a `call` immediate | Final function indices are only known once every unit is placed. |
| `data` | an `i32.const` operand | Data addresses shift as segments are concatenated. |
| `type` | a type index | Type sections merge and deduplicate. |
| `global` | a global index | Only if a unit ever adds globals; today none do. |

**Every patch site must be a fixed-width immediate, and none are today.**
LEB128 is variable width, so patching a small value with a large one would need
the rest of the function moved, which is what a relocation exists to avoid.

The name `EmitSLEB128Fix` looks like it solves this and does not: the "Fix"
there records a sign-extension fix for TP's logical `shr`, and the encoder is
ordinary variable width. That was assumed while drafting this document and
found by reading the implementation, which is worth recording because the
implementation estimate depends on it.

So a `-c` mode needs padded encoders: five bytes for an `i32.const` operand and
five for a call index, whatever the value. This is what `wasm-ld` does for the
same reason. The cost is a slightly larger object; the linker can re-encode
narrowly when it writes the final module, or simply leave the padding, since a
redundant continuation byte is valid LEB128 and every runtime accepts it.

That last point was checked rather than assumed. A hand-assembled module whose
`i32.const 1` is encoded as the five bytes `41 81 80 80 80 00` validates and
returns 1:

```
$ wasm-validate padded.wasm && wasmtime run --invoke f padded.wasm
1
```

Padding only in `-c` mode keeps single-file output byte-identical to what it is
now, which matters because the self-hosting fixpoint compares those bytes.

## The interface description

Generated by the compiler, never written by hand. This is the one point where
the spec review in `notes/spec-review-methods-interfaces.md` and the Excelsior
project independently agreed, which is the strongest external signal available
on any of these questions.

It holds what an importer needs and nothing else: exported constants, types,
variables, and routine signatures. It is emitted as part of the object rather
than as a separate file, so the two cannot disagree.

The importer reads it and adds symbols to its table exactly as if it had parsed
declarations. Because it is generated, a signature cannot drift between
declaration and use — which is the failure the current `{$IMPORT}`/`{$EXPORT}`
mechanism has, where an importer re-declares by hand and a mismatch surfaces at
link time or later.

## Syntax, and how it stays single-pass

```pascal
unit Geometry;

interface

type
  TPoint = record x, y: integer end;

function Distance(const a, b: TPoint): integer;

implementation

function Distance(const a, b: TPoint): integer;
begin
  { ... }
end;

end.
```

The interface section is declarations only. The implementation section repeats
each header in full and supplies the body.

**Repeating the header is deliberate.** Turbo Pascal lets the implementation
omit the parameter list, which means the compiler must remember the interface
signature and match it later — bookkeeping this compiler already carries for
`forward`, but which reads worse: a reader of the implementation cannot see the
signature. Repeating it also makes the implementation section parse exactly
like the declarations the compiler already handles, so the single-pass property
is preserved without new machinery. This follows IP Pascal, whose `forward`
convention the language already adopted.

A unit is single-pass because the interface precedes the implementation, and
within each section declare-before-use holds as it does everywhere else.

## Initialization

**Recommendation: no initialization section, initially.**

A unit may declare variables with initializers, which the compiler already
supports and which run as data-segment contents rather than as code. That
covers most of what an initialization section is used for and costs nothing.

An initialization section raises ordering, which is a real design question and
not a small one: initialization must run in dependency order, a cycle is an
error, and a program that depends on the order of two independent units is
relying on something the language would have to specify. None of that is
needed to reach the exit criterion, and adding it later is additive.

If it is added, the rule should be: initialization runs in the order units were
finished being compiled, dependencies first, and the linker emits calls to each
unit's initializer at the top of `_start`.

## How `uses` tells a system unit from a Pascal one

Phase K gave `uses` a fixed table of system units. A Pascal unit has to share
the clause, and the resolution rule has to be decidable in one pass with no
search:

```pascal
uses Files, Geometry;
```

1. If the name is a **system unit**, it is one. `Files` and `System` are the
   current set.
2. Otherwise it must be satisfied by an **object handed to the compiler** on
   the command line. The compiler matches on the unit name recorded in the
   object, not on the file name.
3. If neither, that is an error naming both possibilities, because "unknown
   unit" is unhelpful when the real problem is a forgotten argument.

**System unit names are reserved.** A Pascal unit may not be called `Files` or
`System`. The alternative — letting a local unit shadow a system one — makes
the meaning of `uses Files` depend on which objects happen to be on the command
line, which is the kind of action at a distance a search path would also bring
and which rule 2 exists to avoid.

## What this does to the host FFI

Nothing. `{$IMPORT}` and `{$EXPORT}` stay exactly as they are: they are the
boundary between Pascal and the host, and units are the boundary between Pascal
and Pascal. A unit may contain `{$IMPORT}` declarations, and its objects carry
those imports for the linker to merge.

The one interaction: two units importing the same host function should produce
one import in the linked module, so the linker deduplicates imports by
(module, name, type) the way it deduplicates types.

## Command line

```
cpas -c geometry.pas -o geometry.cpo     compile a unit to an object
cpas -c shapes.pas   -o shapes.cpo
cpas main.pas geometry.cpo shapes.cpo -o main.wasm
```

The importer finds a unit's interface by being handed the object. There is no
search path, and that is deliberate: a search path is a configuration surface
and a source of "which one did it find" questions, and a build script that
already knows what it is building can pass the paths.

**The linker is a mode of `cpas`, not a separate program.** It shares the
section-writing code that already exists, it keeps the toolchain one binary,
and a separate linker would need its own copy of the WASM encoding rules —
which is exactly the kind of duplication that drifts.

**Staleness is the build system's problem.** `cpas` does not compare
timestamps or hashes and does not decide whether an object needs rebuilding.
A `make` rule does that, as it does for C.

### The limit of "recompiling one unit does not require recompiling the others"

It holds for a change to a unit's **implementation**: rebuild that object,
relink, done.

It does not hold for a change to its **interface**. Every importer read that
interface and put its symbols in its own symbol table, so every importer has to
be recompiled. This is true of every separate-compilation scheme that is not
also a whole-program one, and it is what a build system's dependency edges are
for. Worth stating because the exit criterion could otherwise be read as
promising more than any of these designs delivers.

## What this does not decide

- **Circular dependencies between unit interfaces.** So should this forbid
  them, at least at first. The check is cycle detection over the units named
  in `uses`, the same shape as the include cycle check. Turbo Pascal and
  Delphi permit a cycle between *implementation* sections and not between
  interfaces; ISO 7185 has no units at all, so there is no standard to defer
  to here.
- **Generic or parameterized units.** Not planned, and the non-goals in the
  white paper already rule out the machinery they would need.
- **Whether a unit can be a WASM module boundary for embedding purposes.** A
  host that wants to load a unit separately at run time is asking for Option A
  after all, and it should be evaluated on its own terms if anyone wants it.
- **Whether the compiler itself should be split into units.** `cpas.pas` is
  thirteen thousand lines in one file and is the obvious candidate, which is
  exactly why it should not be the first user. Splitting it would mean the
  fixpoint compares a linked module against a linked module, and the fpc
  bootstrap would need the same split in fpc's own unit system — two moving
  parts added to the one invariant the project leans on hardest. Prove units on
  a three-unit test program first. Splitting the compiler is a separate
  decision with its own risk, and it is not required by anything.

## Review questions

The four the roadmap asks, and where each landed:

| Question | Answer |
|---|---|
| Syntax and single-pass | `unit` / `interface` / `implementation`; headers repeated in the implementation |
| Interface description | Compiler-generated, carried inside the object |
| WASM mapping | Objects plus a linker, one module out. **This is the decision to argue with.** |
| Initialization | None at first; variable initializers cover the common case |

Decided while reviewing this document rather than while writing it, and listed
separately because they were gaps rather than answers:

| Question | Answer |
|---|---|
| `uses Files, Geometry` — which is which | System unit names are reserved and win; anything else must be an object on the command line |
| `{$IMPORT}` / `{$EXPORT}` | Unchanged. Units are Pascal-to-Pascal; the directives are Pascal-to-host. The linker deduplicates identical host imports. |
| Where the linker lives | A mode of `cpas`, not a second binary |
| Rebuild scope | Implementation changes relink; **interface changes force importers to recompile**, which no separate-compilation scheme avoids |
| Splitting the compiler into units | Not first. It would put two moving parts into the fixpoint, and nothing requires it. |
