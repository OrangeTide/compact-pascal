# Contributing to Compact Pascal

Thanks for your interest. This document covers how to build the project, what
the tests check, and what a change is expected to keep true.

## Getting Started

1. Fork the repository at https://github.com/OrangeTide/compact-pascal
2. Clone your fork and create a branch for your work
3. Make your changes
4. Submit a pull request

## Prerequisites

What you need depends on what you are changing.

**Working on the compiler** needs the Free Pascal Compiler (`fpc`), a WASM
runtime (`wasmtime`), and `wasm-validate` from `wabt`. See the
[README](README.md) for install commands.

**Working on the Rust crate** needs Rust 1.85 or later and nothing else. The
compiler snapshot is built into the crate, so no Pascal toolchain and no
separate WASM runtime are involved.

**Building the documentation** needs Pandoc, Typst, and the TeX Gyre fonts.

## Building

```bash
# Bootstrap the compiler and regenerate the snapshot (requires fpc)
make bootstrap

# Build and test the Rust crate
cargo build
cargo test

# Generate PDF documentation
make pdf
```

## Running Tests

```bash
# Everything CI runs, reproducible locally
make test-all

# Everything this machine can check, including things CI does not
make preflight
```

`make preflight` is the one to run before pushing. CI is a second opinion, not
the first one: it takes minutes to answer, it cannot be stepped through, and a
failure there is a worse place to learn something than a failure here.

| Target | What it checks | In CI |
|---|---|---|
| `check-private` | No tracked file leaks a local path or personal identifier | yes |
| `test` | The compiler test suite at default settings | yes |
| `test-checks` | The same suite with checks forced on, then forced off | yes |
| `check-fixpoint` | The committed snapshot is current and self-hosting holds | yes |
| `check-rust` | Crate builds, tests pass, clippy clean, examples run | yes |
| `check-windows` | The Windows cross-build produces the same bytes | yes |
| `check-determinism` | The same source compiled twice gives the same bytes | no |
| `check-selfhost-gen2` | The snapshot's own output is itself a fixpoint | no |
| `check-doc-examples` | Every self-contained example in the docs compiles and runs | no |
| `check-runtimes` | The suite under wasmer as well as wasmtime | no |
| `check-playground` | The playground deploy copies what it should | no |
| `release` | The release artifact builds, and the compiler in it works | no |

**macOS is the one thing preflight cannot cover.** CI is the only place it
runs, so a macOS-specific mistake is the one class of failure that will reach
CI first. Keep shell scripts working under bash 3.2, which is what macOS
ships: no `${arr[@]}` on an empty array under `set -u`, no associative arrays,
no `declare -n`.

`check-windows` and `check-runtimes` skip themselves with a note when the
toolchain is missing, so preflight still runs on a bare machine. A skip is
printed rather than silent, because a check that quietly does nothing is worse
than one that is absent.

### The two invariants

**Self-hosting must hold.** The compiler compiles its own source and the result
must be byte-for-byte identical to the committed snapshot. This is the
project's strongest correctness signal and it has caught bugs no test did.
`make check-fixpoint` verifies it. If you change the compiler, regenerate the
snapshot with `make bootstrap` and commit it alongside your source change.

**The suite must pass with checks on and with checks off.** The two settings
generate different code, so passing one says nothing about the other:
checks-on can hide a codegen bug behind a trap that fires before the wrong
value is observed, and checks-off can hide a bug in the checks themselves.

## Adding a Test

Compiler tests are files, not code. The runner discovers them.

**A program that should work** goes in `compiler-tests/positive/` as
`tNNN_short_name.pas`, with `tNNN_short_name.expected` holding its exact
stdout. Add `.exitcode` if it should exit nonzero (use `134` for a trap; the
runner translates it per runtime), `.input` to feed it stdin, and `.warning`
holding a regex if the compiler should warn. With no `.warning` file the
compiler is expected to say nothing at all, so a stray diagnostic fails.

**A program that should be rejected** goes in `compiler-tests/negative/` as
`nNNN_short_name.pas`, with `nNNN_short_name.error` holding a regex that must
match the compiler's stderr, case-insensitively. A plain substring works, and
is usually the right choice: matching a fragment of the message rather than
all of it leaves room to reword it.

**A compiler invocation** goes in `compiler-tests/cli/` keyed on a name, with
`.args` for the command line and either `.error` or `.diag`.

A test that must pin a directive setting regardless of how the suite is run
should say so in its own source, as `t108` does with `{$S+}`.

## Project Structure

- `compiler/cpas.pas` — the compiler. Changes here affect the core language.
- `compiler-tests/` — the test suite and its shell runner.
- `src/rust/` — the Rust embedding crate.
- `examples/c/` — a reference sample for hosting the snapshot from C. Not a
  library, not built by CI.
- `snapshot/compiler.wasm` — the compiler as WASM. Generated, not edited by
  hand, but committed and expected to be regenerated with any compiler change.
- `doc/` — the language reference, white paper, tutorial, and technical notes.
- `PLAN.md` — the working plan. `ROADMAP.md` is the public summary of it.

## Guidelines

- Keep a pull request to a single change.
- Add tests for a compiler change, both the case that should work and the case
  that should be rejected.
- Keep the three language documents consistent. A change to a language feature
  belongs in `doc/compact-pascal-ref.md`, and the white paper's grammar
  appendix must agree with the reference's.
- Record a design decision in the Findings section of `PLAN.md`, with the
  reasoning. A future reader needs to know why, not only what.
- Do not bump the version in `doc/compact-pascal-ref.md`. Releases are cut
  deliberately.
- Follow the style already in the file you are editing.

### One trap worth knowing

In Pascal source, a `{$` sequence inside a `{ }` comment starts a compiler
directive and ends the comment early. Writing `{ turn this off with {$S-} }`
does not compile. Use the words instead, or a `//` line comment.

## Reporting Issues

Use [GitHub Issues](https://github.com/OrangeTide/compact-pascal/issues).
Please include:

- What you expected to happen
- What actually happened
- Steps to reproduce, ideally a minimal Compact Pascal program
- The compiler version, from the `__version` global or the release you used

For a security issue, see [SECURITY.md](SECURITY.md) instead.

## License

This project is dedicated to the public domain under
[CC0 1.0 Universal](LICENSE). By contributing, you agree to release your
contribution under the same terms, waiving any copyright and related rights to
the extent the law allows.

If you cannot make that dedication for work you are submitting, say so in the
pull request rather than submitting it anyway.
