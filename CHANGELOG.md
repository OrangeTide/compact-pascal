# Changelog

Notable changes to Compact Pascal: the language, the compiler, and the Rust
embedding crate.

The language and its reference use [Calendar Versioning](https://calver.org/)
on a `YY.MM.minor` scheme. The Rust crate versions separately and will follow
[Semantic Versioning](https://semver.org/) from 1.0; see the API stability
policy in [EMBEDDING-GUIDE.md](EMBEDDING-GUIDE.md) for what that will and will
not freeze.

Entries describe what changed for someone using the project. The reasoning
behind a decision lives in the Findings section of `PLAN.md`.

## Unreleased

### Language

- **Pointers.** `^T` pointer types, `p^` dereference, `@x` address-of, `nil`,
  and pointer comparison with `=` and `<>`. Pointers work as parameters, as
  record fields, and as array elements. There is no heap yet, so a pointer must
  target storage that already exists.
- **Forward pointer references.** `PNode = ^TNode` may precede the declaration
  of `TNode` within the same `type` block. This is the language's only
  exception to declare-before-use.
- Ordering comparisons on pointers (`<`, `>`, `<=`, `>=`) are a compile error
  rather than address comparison. Turbo Pascal permits them; Compact Pascal
  does not.
- `write` and `writeln` reject a pointer argument.
- **`{$S+/-}` (`{$STACKCHECKS}`) directive**, on by default. Controls the stack
  overflow guard, the frame balance check, and the nil check.

### Compiler

- **Stack overflow is detected.** Every prologue compares the stack pointer
  against the end of the data segment before reserving its frame and traps if
  the frame would cross it. Deep recursion previously walked down through the
  heap and data segment silently.
- **The stack pointer is restored from the recorded frame base** at function
  exit rather than by adding the frame size back. An unbalanced allocation
  inside a body is now contained to that one call instead of desynchronizing
  the stack pointer for the rest of the program. Under `{$S+}` a mismatch traps
  at the function that caused it.
- **Dereferencing `nil` traps** under `{$S+}` instead of reading the nil guard
  and returning a zero the program never stored.
- New `-R+`/`-R-` and `-S+`/`-S-` command-line switches set the check state a
  source file starts with. A directive in the source still overrides from where
  it appears.
- Accepts a leading UTF-8 byte order mark.
- Fixed stdout binding that depended on `/dev/stdout` and so failed on macOS
  and produced an empty file on Windows.

**Known limitation:** `with p^ do` is rejected. Use `p^.field`. Assignment
between pointer types with different targets is not yet checked.

### Rust crate

- **`Options`** carries the compiler's switches: range checks, stack checks,
  conditional-compilation defines, and verbosity.
- **`Diagnostic` and `Severity`** parse the compiler's tagged stderr, so a host
  can report a line and column instead of a blob of text. `CompileError` now
  distinguishes a rejected program from a compiler fault from an unresolved
  include.
- **`Limits`** bounds what a compiled program may consume: `fuel` for
  execution and `memory_bytes` for linear memory. Neither is on by default.
- **`RuntimeError` distinguishes an exit from a trap.** `halt(3)` arrives as
  `RuntimeError::Exit(3)`; a trap arrives as `RuntimeError::Trapped`. The
  previous code could not tell them apart, because `proc_exit` was signalled
  through an error message that every call site matched with a substring
  search.
- **The WASI bridge is complete.** `args_sizes_get` and `args_get` were stubs
  returning zero arguments and now serve a real argument vector. `fd_write` and
  `fd_read` validate the file descriptor and answer `EBADF` rather than
  reporting success for a descriptor that does not exist.
- Three examples: `hello`, `calculator`, and `host-callback`, each covered by
  the test suite and run in CI.

### Documentation

- **[EMBEDDING-GUIDE.md](EMBEDDING-GUIDE.md)**, covering compiling,
  diagnostics, running, calling in both directions, strings, includes, what the
  sandbox does and does not protect, and the API stability policy.
- **[SECURITY.md](SECURITY.md)** with a disclosure process and an explicit
  threat model naming what is in scope and what is not.
- The reference gained a Pointers section, a Conformance statement with minimum
  limits, a Versioning and Stability policy, and a Defined and Undefined
  Behavior section stating what the compiler actually does rather than what it
  was assumed to do.
- Directives are recognized in the `{$...}` form only. `(*$R+*)` is a comment
  and is silently ignored, unlike in Turbo Pascal. This was a documentation
  error, not a change: the compiler never supported the second form.
- Zig is removed from the documentation. It was never implemented and is not
  planned; `ROADMAP.md` states why.

### Project

- **The license is [CC0 1.0 Universal](LICENSE)**, matching what the source
  files have always said. The MIT and Apache-2.0 files are removed. The
  README and `Cargo.toml` previously disagreed with each other and with the
  sources.
- CI runs the compiler suite on Linux and macOS, cross-compiles for Windows and
  runs it under Wine, and runs the whole suite twice: once with checks on and
  once with checks off.
- `make test-all` reproduces everything CI runs.
- A guard fails the build if a tracked file leaks a local filesystem path or a
  personal identifier.

## 26.08.0 — 2026-08-01

Language reference and white paper published as version 26.08.0. Compiler
self-hosts with a validated fixpoint. Browser playground shipped.

## 26.04.1 — 2026-04-10

Documentation fixes.

## 26.04.0 — 2026-04-07

First tagged release.
