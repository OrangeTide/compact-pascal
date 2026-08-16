# Compact Pascal Roadmap

This is the public plan. It says what is committed, what is deferred, and what
will never be built, so you can judge whether the project is going somewhere you
want to follow.

`PLAN.md` in this repository is the working document behind it, with the design
rationale and the checklists. This page is the summary.

**Status: pre-1.0.** The language is a beta. See
[Versioning and Stability](doc/compact-pascal-ref.md#versioning-and-stability)
in the language reference for what that means for your code. In short: pin an
exact version, and expect changes without a deprecation period until 1.0.

## Where 1.0 is

1.0 is declared when the specification is closed, CI gates every change, the
embedding story is proven in one language, and the compiler has runtime checks
that make memory corruption loud instead of silent. Not when the feature list is
finished.

| Phase | Goal | Status |
|---|---|---|
| A | Specification closure | Done |
| B | FFI snapshot hang | Done |
| C | CI, fixpoint gating, release artifact | Done |
| D | Runtime safety instrumentation | Done |
| E | Pointer types | Done |
| F | Rust embedding to production grade | Done — **1.0 is ready to cut** |
| G | C library: ship-or-defer decision | Done — dropped, see below |

**1.0 means trustworthy, not capable.** Closed specification, CI gating every
change, a proven embedding, and failures that are loud instead of silent. It is
deliberately still single-file, and it was still heapless when 1.0 was scoped.
That is a real limit and it is stated here rather than discovered later.

What makes the language capable enough for arbitrary programs comes after, and
is roughly as much work again:

| Phase | Goal | Status |
|---|---|---|
| H | Structured and string return types — `function F: string` | Done |
| I | Heap: `New` and `Dispose` | Done |
| J | File system access and the `text` type; `{$I}` inside the compiler | Done |
| K | System units — `uses` against runtime-provided bindings | Done |
| L | Pascal units — write and compile your own, separately | Done |
| M | Method pointers and interfaces | |

Phases are capped at about three weeks each so that a wrong estimate stays
contained. Phase L breaks that cap and is split into design and implementation
for exactly that reason. This is a solo project; treat the ordering as firm and
any date as a guess.

### The two limits people ask about first

**Allocation.** Solved in Phase I. `New` and `Dispose` work over a first-fit
free list, so lists and trees can be written. The allocator does not split or
coalesce blocks, so a program mixing many sizes will fragment; one that
allocates and frees the same shapes reuses its memory exactly. Running out
traps rather than returning `nil`.

**Program size.** Solved for includes in Phase J. `cpas -I` resolves `{$I}`
itself, eight levels deep, with cycles and missing files diagnosed, so a
multi-file program builds from the command line with no host help. The
host-side expansion path stays supported and is still the default. Real units,
where a file is compiled once rather than textually inserted, are done: a unit
compiles to an object and a program links against it.

## What is deliberately not planned

Recorded so nobody waits for something that is not coming.

- **A Zig embedding library.** Not deferred, not planned. The Zig project asks
  that contributions not be machine-generated, and this compiler is
  substantially machine-written, so a Zig binding cannot be offered in good
  faith. Earlier documentation advertised one; that was wrong and has been
  corrected.
- **A C embedding library.** Removed, not deferred. A partial one lived in
  `src/c` for a while and has been deleted along with the vendored copy of
  wasm3 it never used.

  The design was bring-your-own-runtime: the host supplied a WASM engine
  through a vtable, and the library sat on top. That is the wrong split. The
  engine binding is the hard half, and a C user who has written it is most of
  the way to running the compiler snapshot themselves. What the library would
  have added on top was thin, and the parts that needed an engine, including
  `cp_compile` itself, were never written.

  The Rust crate's value comes from exactly what C cannot have: one dependency
  with the compiler snapshot and a runtime already inside it. There is no
  equivalent trick in C, so the library would have stayed a wrapper around
  work the user still has to do.

  What replaces it is smaller and honest. The host contract is five WASI
  imports, specified in the language reference under "Implicit WASI Imports",
  and `examples/c/hello` is a working sample that implements them against
  wasm3 in about 300 lines. That sample is documentation, not a supported
  library, and it says so.
- **An LSP server, editor extensions, or a source-level debugger.** The browser
  playground covers the interactive case for now.
- **Exception handling.** Incompatible with single-pass compilation. Use error
  codes.
- **Generics, closures, reflection, async.** See the white paper for why each
  conflicts with the architecture rather than merely being unbuilt.
- **Dynamic arrays.** Not planned as a language feature. With the Phase I heap
  in place, a pointer to a manually sized block covers the same ground without
  a hidden allocation in the type system.
- **Floating point, and Unicode `rune` support.** Deferred without a date.

## Standing invariants

Every phase boundary holds these, without exception:

1. **The self-hosting fixpoint is byte-identical.** The compiler compiling its
   own source reproduces itself exactly. One byte of difference is a regression.
2. **The committed snapshot matches the source.** A compiler change cannot land
   with a stale binary.
3. **The test suite passes**, on Linux and macOS.
4. **Diagnostics stay on stderr.** The compiled module goes to stdout, so a
   misrouted message corrupts output rather than merely looking untidy.

`make test-all` runs what CI runs.

## Getting it

`make release` builds a zip holding `compiler.wasm`, a README, and the licence.
It is deliberately the smallest useful thing: a user with a WASM runtime needs
nothing else, and a user without one is not helped by a zip. No installer, no
native binary, no platform matrix.

```
wasmtime run compiler.wasm < hello.pas > hello.wasm
wasmtime run hello.wasm
```

The build verifies itself before packaging: the module must validate, compile a
program, and that program must run. Releases are cut deliberately rather than
on every tag.

## Reporting problems

Bugs, specification ambiguities, and cases where the compiler disagrees with the
language reference are all worth reporting. The reference is authoritative: if
they disagree, that is a bug in one of them, and which one is a decision rather
than an assumption.
