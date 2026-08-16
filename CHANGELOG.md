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
- **A heap: `New` and `Dispose`.** A first-fit free list between the data
  segment and the stack, so lists and trees can be written at last. The size
  comes from the pointer's target type, not from an argument.

  `Dispose` sets the pointer to `nil`, which standard Pascal does not. It turns
  a use after dispose, and a double dispose, into a trap instead of a read of
  memory that now belongs to something else. Other pointers to the same block
  are still dangling.

  The allocator does not split or coalesce blocks, does not compact, does not
  collect garbage, and does not return memory to the heap end. Running out
  traps rather than returning `nil`. See "The Heap" in the reference.
- **A `var` argument may now be a field or a dereference**, not only an array
  element: `Insert(t^.left, v)` works. Previously only `[index]` was accepted.
- **System units and the `uses` clause.** `uses Files;` after the program
  header makes the `text` type and the file routines visible and adds
  `path_open`, `fd_close`, and `fd_prestat_get` to the module's imports, so a
  host can see from the import list whether a program wants files. `uses
  System;` is accepted and does nothing. An unknown unit is an error.

  A system unit is not compiled: nothing is read from disk and nothing is
  linked. Separately compiled units are a later phase.

  Because the file routines are no longer always on, a program that does not
  use them may declare its own `Assign`, `Reset`, `Rewrite`, or `Close`.

  **`uses` is now a reserved word.** A program that used it as an identifier
  no longer compiles. This is the only backward-incompatible change in this
  release.
- **Text files.** `text` is a real type. `Assign`, `Reset`, `Rewrite`,
  `Close`, `Write`/`WriteLn` to a file, `ReadLn(f, s)`, `Eof(f)`, and
  `IOResult`. Names resolve inside a directory the host preopens, and nothing
  outside it is reachable.

  `{$I+}`, the default, traps where an operation fails. `{$I-}` records the
  error instead; `IOResult` returns it and clears it, so reading twice gives
  zero the second time, as in Turbo Pascal.

  `Read(f, c)` takes a single character; `ReadLn(f, s)` takes a line. Reading
  past the end of a file is an error rather than a quiet `chr(0)`: a zero byte
  is a legal thing to find in a file, so returning one for "there was nothing
  there" would leave a program unable to tell the two apart. It traps under
  `{$I+}` and sets `IOResult` to 200 under `{$I-}`. `IOResult` values below 200
  are the host's WASI errno; 200 and above are defined by this language.

  Not yet:
  no `Append`, no `Seek`, no `file of T`, no reading a number straight from a
  file, and a concatenation in a file write is rejected rather than compiled.
  See "Text Files" in the reference.
- **Procedural types.** `type TBinOp = function(a, b: integer): integer;` names
  a signature, `@Add` produces a value, and calling the variable calls what it
  holds. Values assign, pass as parameters, sit in records and arrays, and
  compare with `=` and `<>`.

  A routine whose address is taken goes into the module's function table, and
  the call is a WASM `call_indirect`. Both are WASM 1.0, so this costs no
  additional proposal. Table slot zero is left empty, so calling a procedural
  variable that was never assigned traps instead of reaching an unrelated
  routine.

  Three things are rejected rather than left to trap: a routine whose
  signature does not match the type it is assigned to, a call with the wrong
  number of arguments, and taking the address of a *nested* routine, which
  would arrive with the display describing the wrong frame. The signature
  check compares the parameter count and whether there is a result, not the
  Pascal types of the parameters, because every scalar is an `i32` by then.

  There is no `nil` for a procedural type, and at most 64 distinct routines
  may have their addresses taken. See "Procedural Types" in the reference.
- **Standalone methods.** `function Area for (r: TRect): integer;` attaches a
  method to a record without touching the record's declaration, and
  `MyRect.Area` calls it. A pointer receiver, `procedure Grow for (r: ^TRect)
  (k: integer);`, can mutate; a value receiver gets a copy and cannot. A
  pointer designator is dereferenced automatically, so `p.Area` and `p^.Area`
  are the same, and a value receiver called on a pointer works the same way.

  The receiver must be a record. A method's name is not a name in ordinary
  scope: it is reachable only through a receiver, so it cannot collide with a
  procedure, and `Area(r)` is not a way to call it.

  Two things are rejected. A method may not share a name with a field of its
  receiver type, reported at the declaration rather than at the call, because
  the declaration is where the mistake is. A method called on a function
  result is refused, because a result is a temporary with no address to hand
  a receiver.

  The receiver is passed as the last parameter and a call is an ordinary WASM
  `call`; nothing is dispatched at run time. See "Standalone Methods" in the
  reference.
- **Interfaces and `implement` blocks.** An interface names a set of method
  signatures; an `implement IPet for TCat;` block declares that a record
  satisfies it, and the compiler verifies that when the block closes. Each
  signature is satisfied either by a method written in the block, where `Self`
  is a pointer to the receiver, or by a standalone method the type already
  had. A type that already has the method it needs writes nothing.

  Assigning a conforming record to an interface variable builds the value:
  `Self` plus one function table index per method, an inline vtable. A call
  through it is a WASM `call_indirect` with `Self` as the trailing argument,
  which is exactly how a standalone method receives its receiver, so one
  routine serves both `MyCat.Greet` and `Pet.Greet` with no wrapper.

  The conversion happens on assignment only. `SayHello(MyCat)` is a compile
  error asking you to assign to an interface variable first, because the
  conversion builds a value and an argument has nowhere to put it.

  An interface method cannot return a `string`, record, or array, and an
  interface may declare at most 8 methods. See "Interfaces" in the reference.
- **The compiler resolves `{$I}` itself under `-I`.** A multi-file program
  builds from the command line with no host help, eight levels deep, with
  cycles and missing files diagnosed instead of silently skipped. Without the
  flag the directive is skipped as before, so source an embedder already
  expanded is not opened twice.

### Rust crate

- **Version 0.2.0.** `Options` and `Limits` are now `#[non_exhaustive]` and are
  built with `Options::new()` and `with_` methods rather than a struct
  literal. Done before 1.0 deliberately: the attribute is what makes a field
  added later a non-breaking change, and after 1.0 the first new option would
  have cost a major version.

  `Options` also gained `unit_dir` and `objects`, and `RuntimeError::Execution`
  was renamed, so this release breaks anything written against 0.1.0. Under
  0.x that is a minor bump, and a dependency written as `"0.1"` will not pick
  it up.
- **`Options::unit_dir` and `Options::objects`** link a program against
  separately compiled units. See "Linking separately compiled units" in the
  embedding guide.

- **`Options::include_dir`** lets the compiler resolve `{$I}` itself, against
  one directory. **`Limits::preopen_dir`** grants a compiled program its own
  directory to open files in. Both are `None` by default, and with neither set
  every open is refused.

  The compiler snapshot now declares `path_open` and `fd_close` because it can
  resolve includes, and declaring an import is not the same as being allowed
  to use it: a host that sets neither field keeps exactly the behavior it had.
- **Functions may return a `string`, `string[n]`, record, or array.**
  `function F: string` was previously rejected outright. The result is
  caller-allocated and released at the end of the statement; loops release each
  iteration. Assigning to a *field* of the result, `MakePoint.x := 1`, is not
  supported and reports what to do instead. An `external` function may not
  return a structured type.

  A named string return type used to compile by accident and returned the
  address of the callee's dead frame, so `F(1) + F(2)` printed the second value
  twice. If you relied on that path, it now copies correctly.

### Compiler

- **A damaged object is diagnosed rather than believed.** Counts and lengths
  in an object were never checked, so a count of `` read as -1 and a
  loop over it ran zero times: a corrupt object was silently treated as
  having no types and compiled anyway. Other values crashed. Every count is
  now bounded by what the compiler could have written.
- **A directory given where a file was expected crashed** with an unhandled
  runtime error rather than a diagnostic, both as an object on the command
  line and as an include. Opening a directory succeeds under the native
  build and fails on the first read; the WASM build was already correct,
  because WASI refuses to open one. An empty object now says it is empty
  rather than reporting a record that ends early.
- **A `for` loop whose body called a routine containing its own `for` loop
  ran the wrong number of times.** The loop limit lived in a data slot
  indexed by lexical nesting depth, and a lexical index is not unique at run
  time: a loop in a called routine had the same depth as the caller's and
  overwrote its limit. A loop that should have run once ran eight times. The
  limit now lives in a local of the enclosing routine, which is per
  invocation, so neither a call nor recursion can reach another frame's.

  This affected every program the compiler produced, including its own
  snapshot, and is why the snapshot behaved differently from the
  fpc-built compiler.
- **Closing a file that was written and then read appended a second copy of
  the data.** The buffer flush wrote whatever byte count the control block
  held, and the read path uses that same field for the bytes it has
  buffered. So write, close, reopen the same `text` variable with `Reset`,
  read anything, close, and the file had grown by the size of the read
  buffer. The flush was documented as a no-op outside write mode and did not
  check the mode.
- **Using a method's name without a receiver says so.** `Area(q)` or `@Area`,
  where `Area` is a standalone method, reported "undeclared identifier",
  which sends you looking for a declaration that is sitting right there. It
  now names the receiver type. A method defined in an `implement` block names
  the interface instead, because that one is not dot-callable on the concrete
  type either.
- **Argument counts are checked.** Calling a routine with the wrong number of
  arguments was never diagnosed. The call emitted a module that failed WASM
  validation, or, with too many arguments, one whose extra values were left
  on the stack. This affected every call, not only methods.
- **Structured assignment is type-checked.** `a := b` between two unrelated
  record types compiled and copied the destination's size in bytes. The
  source's type is now compared when it is known, which covers a designator;
  a value whose type the expression parser does not report is still not
  checked.
- **A structured result cannot be discarded.** `Tag;` where `Tag` returns a
  string emitted an invalid module. It is now an error naming what to do.
- **A function returning an interface must be assigned an interface value.**
  Assigning a concrete record copied it into an interface-sized buffer and
  never built the vtable. Converting there is possible but pointless: `Self`
  would point at a local of the function that is about to return.
- **`$sp` started at the wrong address when a module needed more than one
  page.** It was initialized to `{$MEMORY}` pages worth of bytes rather than
  to the top of the memory the module actually asked for, so a program whose
  data segment spilled past `{$MEMORY}` began with its stack inside the data
  segment and trapped on the first call. Found when the compiler's own data
  grew past its setting.
- **`{$STACKSIZE}` now means something.** It was parsed, validated, printed
  under `-v`, and then ignored: the initial memory was sized for the data
  segment alone and the stack got whatever was left in the last page. Initial
  memory now covers the data segment plus the requested stack.
- The compiler's code section buffer grows from 192 KB to 256 KB, and its own
  `{$MEMORY}` from 192 to 256 pages. The snapshot's initial linear memory
  therefore grows from 12.5 MB to 16.7 MB.
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

- **Concatenation across a call is fixed.** The pieces of a pending `+` chain
  were held at one fixed address, so a callee that concatenated overwrote its
  caller's pieces. `a + Wrap(b)` produced the wrong string, and a recursive
  string function returned empty. Pieces are now protected across a call.

**Known limitations:** a user procedure cannot be named `Insert`, `Delete`,
`New`, or `Dispose`; those names are matched as built-ins before symbol lookup,
and the resulting error talks about the built-in's arguments. The file
routines used to have the same problem and no longer do, because `uses Files`
gates them. `with p^ do` is
rejected; use `p^.field`. Assignment
between pointer types with different targets is not yet checked. Concatenating
two or more `char` values in one expression, `a + '.' + b + '.'`, aliases a
shared conversion buffer and gives the wrong answer; concatenate strings
instead. That last one is long-standing, not new.

### Rust crate

- **`Options`** carries the compiler's switches: range checks, stack checks,
  conditional-compilation defines, and verbosity.
- **`Diagnostic` and `Severity`** parse the compiler's tagged stderr, so a host
  can report a line and column instead of a blob of text. `CompileError` now
  distinguishes a rejected program from a compiler fault from an unresolved
  include.
- **`Limits`** bounds what a compiled program may consume: `fuel` for
  execution and `memory_bytes` for linear memory. Neither is on by default.
- **Include paths are confined to their base directory.** `expand_includes`
  and `compile_with_includes` refuse a path containing `..`, an absolute path,
  or a drive prefix. Previously the filename was joined onto the base
  directory with no check, and joining an absolute path discards the base, so
  `{$I '/etc/passwd'}` read that file. Found while reviewing the threat model
  in `SECURITY.md` against the code.
- `RuntimeError::Execution` is renamed `RuntimeError::Memory`. After the change
  above it was only raised by the string helpers, never by execution, so the
  name said the wrong thing. Renamed now rather than after 1.0 freezes it.
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

### Corrected documentation

- **"Programs without I/O have zero implicit imports" was never true.** Every
  compiled module declares the five core WASI imports whether or not it calls
  them, because import indices are positional and are fixed before parsing so
  that helper function indices stay stable in a single pass. The claim was in
  the language reference, the white paper, and the README. The conformance
  requirement now distinguishes what a module declares from what it calls.

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

### Removed

- **The C embedding library** (`src/c`) and the vendored copy of wasm3
  (`vendor/wasm3`). Everything in it that needed a WASM engine was a stub,
  including `cp_compile`, so it could never compile Pascal. The design put the
  engine binding on the user, which is the hard half of the job, leaving the
  library as a thin wrapper over work the user still had to do. `ROADMAP.md`
  records the reasoning under "What is deliberately not planned".
- `make all-c`, `make lib-c`, `make lib-wasm3`, `make example-c-hello`,
  `make clean-c`, and `make clean-rust`. `make all` now bootstraps the compiler
  and runs `test-all`; the Rust crate is cleaned with `cargo clean`.

`examples/c/hello` is kept as a reference sample showing how to host the
compiler snapshot from C against upstream wasm3, in about 300 lines. It is
documentation, not a library, and it says so.

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
