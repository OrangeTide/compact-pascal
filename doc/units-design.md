# Separately Compiled Units: Design

Status: **proposal, for review.** This is Phase L1 of `PLAN.md`. Nothing here
is implemented. It exists so the design can be argued with before four weeks
of implementation are spent on it.

**Revised after Phase M.** Procedural types, standalone methods, and
interfaces landed after this document was first written, and they add three
things a linker has to handle that were not accounted for here. They are
folded into the sections below and summarized under "What Phase M changed".

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
elements    the functions this unit put in the table, in its own order
relocations one entry per patch site
```

A relocation is `(offset, kind, symbol)`, where kind is one of:

| Kind | Patches | Why it is needed |
|---|---|---|
| `func` | a `call` immediate | Final function indices are only known once every unit is placed. |
| `data` | an `i32.const` operand | Data addresses shift as segments are concatenated. |
| `type` | a type index | Type sections merge and deduplicate. |
| `table` | an `i32.const` operand | A procedural value *is* a table slot number, and slots renumber when two units' tables merge. |
| `global` | a global index | Only if a unit ever adds globals; today none do. |

The `table` kind is the one this document originally missed, and it is not a
variant of `data`. `@Add` compiles to `i32.const <slot>` and an interface
conversion compiles to one `i32.const <slot>` per method, both filled in from
a table the compiler numbers from 1 upward within a single compilation. Two
units each numbering from 1 collide, so the linker assigns final slots and
patches every site. Slot 0 stays empty in the linked module for the same
reason it does today: it is what makes an unassigned procedural variable trap
rather than call something arbitrary.

### Data relocations need the emitter to know an address from a number

Measured rather than estimated. `i32.const` carries both, and the compiler
has 92 sites that emit one: 64 name a compiler-owned buffer and are
unambiguous by name, and 28 push `syms[sym].offset`, which is a data address
for a string literal or a typed constant and a plain value for an ordinary
constant. Those 28 need reading one at a time.

A base-relative alternative was considered and does not help. Adding a
`__data_base` global that unit code adds to every data reference removes the
relocation, but it needs to know which `i32.const`s are addresses in order to
add to them, which is the same problem with a runtime cost attached.

So: an `EmitDataAddr` beside `EmitI32Const`, and the conversion done site by
site. The risk worth naming is that a missed site is silent. It emits an
address that was right for the unit alone and is wrong once the data segments
are concatenated, and it fails as a wrong value read from the wrong place at
run time, far from the cause. Two things reduce it: the conversion is
mechanical for the 64 named ones, and a linked three-unit program that
exercises strings is a test that would catch a miss in the remaining 28.

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
variables, routine signatures, and **conformances**. It is emitted as part of
the object rather than as a separate file, so the two cannot disagree.

Conformances are the fourth item and were not in the first draft. When a unit
writes `implement IPet for TCat;` the fact that TCat satisfies IPet, and which
routine implements each signature, is what makes `Pet := MyCat` legal. It is
held today in a compile-time table that dies with the compilation. An importer
that can see `TCat` and `IPet` but not the conformance between them cannot
perform the conversion, so the pair and its method routines have to travel in
the object.

The importer reads it and adds symbols to its table exactly as if it had parsed
declarations. Because it is generated, a signature cannot drift between
declaration and use — which is the failure the current `{$IMPORT}`/`{$EXPORT}`
mechanism has, where an importer re-declares by hand and a mismatch surfaces at
link time or later.

## What Phase M changed

Three things, of which two are ordinary linker work and one is a change the
compiler needs before a linker is written at all.

**Table slots need relocating.** Covered above as the `table` relocation kind.
Ordinary work.

**Conformances need exporting.** Covered above. Ordinary work.

**Method symbol names do not survive separate compilation.** This one is not
a relocation and cannot be fixed in the linker. **Fixed ahead of L2**; the
description below is kept because it is why the scheme is what it is.

A standalone method is registered in the symbol table under a name no source
can spell, `#<typeIdx>.<NAME>`, where `typeIdx` is the type's index in the
compiler's descriptor array. A call site knows the descriptor of the
designator it just parsed, so keying on the index costs nothing and needs no
lookup. Within one compilation that is exact.

Across compilations it is meaningless. The index is a counter over the types
a single run happened to see, in the order it saw them. `TPoint` might be 3 in
the unit that declares it and 7 in the unit that imports it, or the importing
unit might never build a descriptor for it at the same position. An importer
cannot form the key, so it cannot find `Distance` at all.

The key is now the type rather than where the type landed:
`#<Unit>.<TypeName>.<NAME>`. A type descriptor carries the unit-qualified
name it was first declared under, which is what lets a call site holding only
a descriptor recover it. First name wins, so `B = A` shares A's descriptor
and its methods rather than renaming it.

A type declared inside a routine gets its descriptor index appended,
`#<Unit>.TR$7.<NAME>`. Only a top-level type can be exported, so only a
top-level name has to be stable; without the suffix a local `TR` and a global
`TR` produce the same key and their methods look like duplicates of each
other. Diagnostics strip both the unit prefix and the suffix, neither of
which is anything the author wrote.

Done before the linker rather than during it, because every part of the
object format that refers to a method refers to it by this name, and changing
the naming scheme afterwards would mean changing the format. What remains for
L2 is to set the unit name from a `unit` header instead of the `program` one.

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

## Memory sizing is the linker's job

Not mentioned in the first draft, and worth stating because getting it wrong
is a bug this project has already had once. The linked module's initial memory
must cover the *merged* data segment plus the stack, and the stack pointer's
initializer must be the top of that memory rather than of whatever
`{$MEMORY}` any one unit asked for. A linker that concatenates data segments
and leaves the memory section alone reproduces exactly the defect fixed in
Phase M, where a program whose data outgrew its setting began with its stack
inside the data segment and trapped on the first call.

Which unit's `{$MEMORY}`, `{$MAXMEMORY}`, and `{$STACKSIZE}` win is an open
question. The simplest rule that cannot surprise anyone is that they are
program-level settings and a unit may not set them.

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
  fifteen thousand lines in one file and is the obvious candidate, which is
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

Found by re-reading this document against the compiler after Phase M, and
listed separately again because they were misses rather than answers:

| Question | Answer |
|---|---|
| Procedural values across units | A new `table` relocation kind. A procedural value is a table slot number, and two units both numbering from 1 collide. |
| Conformances across units | Carried in the interface description. `implement IPet for TCat` is a fact an importer needs and the first draft did not export it. |
| Method names across units | **Fixed ahead of L2.** The mangling keyed on the type's descriptor index, a counter over one run, so a second compilation could never form the key. Now `#<Unit>.<TypeName>.<NAME>`, carried on the type descriptor. Only setting the unit name from a `unit` header remains. |
| Memory sizing of the linked module | The linker's job, and the place a fixed bug could come back. Initial memory must cover merged data plus stack, and `$sp` must start at the top of it. Proposed: `{$MEMORY}`, `{$MAXMEMORY}`, and `{$STACKSIZE}` are program-level and a unit may not set them. |

### Effect on the estimate

The four-week figure stands, with the work redistributed. The `table`
relocation and conformance export are the same kind of work already counted
for `func` and `data` relocations. The method renaming is new and is not part
of the linker: it is about a day, and it is the one item that should be done
first, because the object format encodes method names.
