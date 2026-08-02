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
| C | CI and fixpoint gating | In progress |
| D | Runtime safety instrumentation | Not started |
| E | Pointer types | Not started |
| F | Rust embedding to production grade | Not started — **1.0 here** |
| G | C library: ship-or-defer decision | Not started |
| H | Method pointers | Not started |
| I | Module system design, specification only | Not started |

Phases are capped at about three weeks each so that an estimate being wrong
stays contained. This is a solo project; treat the ordering as firm and any date
as a guess.

## What is deliberately not planned

Recorded so nobody waits for something that is not coming.

- **A Zig embedding library.** Not deferred, not planned. The Zig project asks
  that contributions not be machine-generated, and this compiler is
  substantially machine-written, so a Zig binding cannot be offered in good
  faith. Earlier documentation advertised one; that was wrong and has been
  corrected.
- **A C embedding library before 1.0.** Deferred. Rust proves the embedding
  design first. Three libraries in flight means three unfinished ones.
- **An LSP server, editor extensions, or a source-level debugger.** The browser
  playground covers the interactive case for now.
- **Exception handling.** Incompatible with single-pass compilation. Use error
  codes.
- **Dynamic arrays, generics, closures, reflection, async.** See the white paper
  for why each conflicts with the architecture rather than merely being unbuilt.
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

## Reporting problems

Bugs, specification ambiguities, and cases where the compiler disagrees with the
language reference are all worth reporting. The reference is authoritative: if
they disagree, that is a bug in one of them, and which one is a decision rather
than an assumption.
