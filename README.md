# Compact Pascal

<p align="center">
  <img src="pages/logo/compact-pascal-readme.png" alt="Compact Pascal" width="400">
</p>

![Status: Phase 1 Complete](https://img.shields.io/badge/status-phase%201%20complete-green)
![License: CC0-1.0](https://img.shields.io/badge/license-CC0--1.0-blue)
![WASM Target: 1.0 MVP](https://img.shields.io/badge/WASM-1.0%20MVP-purple)
[![Human–AI Co-Created](https://dotnetdave.github.io/ai-usage-badges/badges/svg/human-ai-co-created.svg)](https://dotnetdave.github.io/ai-usage-badges/)

An embeddable Pascal-to-WebAssembly compiler. The compiler is written in Pascal, compiles to WASM 1.0, and ships as a self-contained WASM binary. Embedding libraries let you compile and run Compact Pascal programs from your application — no external Pascal toolchain required. Rust is the supported target; a C library is planned after it.

## Overview

Compact Pascal is a new language in the Pascal family. It inherits Pascal's syntax and strong typing while making deliberate departures for embeddability:

- **No I/O runtime library** — `write`/`writeln`/`read`/`readln` are compiler intrinsics that lower to WASI host imports. No file types. Programs without I/O have zero implicit imports.
- **Minimal runtime** — the compiled WASM output has no standard library overhead. Host applications provide exactly the functionality they want.
- **Single-pass compiler** — fast compilation, especially important when the compiler itself runs inside a WASM interpreter.
- **WASM 1.0 MVP only** — no WASM extensions, maximum portability across runtimes.
- **Modern extensions** — structural interfaces with `implement` blocks (Go-style), short-circuit `and then`/`or else` (ISO 10206).

### How It Works

```
┌───────────────────────────────────────────────────┐
│  Your Application (Rust / C / Browser JS)         │
├───────────────────────────────────────────────────┤
│  Embedding Library (compact─pascal crate/module)  │
│  ┌────────────────┐   ┌───────────────────────┐   │
│  │ WASM Runtime   │   │ Host─Guest FFI        │   │
│  │ (wasmi / wasm3)│   │ (imports / exports)   │   │
│  └────────────────┘   └───────────────────────┘   │
├───────────────────────────────────────────────────┤
│  Compiler (WASM blob, written in Pascal)          │
│  source → [fd 0] → compiler → [fd 1] → .wasm      │
├───────────────────────────────────────────────────┤
│  Compiled Program (WASM module)                   │
│  executed by the same WASM runtime                │
└───────────────────────────────────────────────────┘
```

The compiler ships as a pre-compiled WASM binary embedded in the library. Your application feeds Pascal source in, gets a WASM module out, and runs it — all in-process.

### Quick Example (Rust)

```rust
use compact_pascal::{Compiler, Instance};

let result = Compiler::new()
    .compile("program Hello; begin writeln('Hello!') end.")?;
Instance::new(&result.wasm)?.run()?;
```

Compiling at run time is the point: the Pascal source can come from a file, a
database, or a user. See [EMBEDDING-GUIDE.md](EMBEDDING-GUIDE.md) for calling
into Pascal, registering host callbacks, reading diagnostics, and bounding what
a guest may consume. Working examples are in `examples/rust`.

## Status

**Phase 1 complete.** The compiler is written, self-hosts (fixpoint validated), and has 132 tests (108 positive, 19 negative, 5 command-line), each run with checks on and with checks off. A browser playground is shipped. The C embedding library is partially implemented. See the [roadmap](ROADMAP.md) for what is committed, deferred, and not planned; [PLAN.md](PLAN.md) is the working document behind it.

**Standalone usage (no embedding library needed):**

```bash
wasmtime run compiler.wasm < hello.pas > hello.wasm
wasmtime run hello.wasm
```

| Phase | Description | Status |
|---|---|---|
| 1 | Compiler (Pascal, bootstrapped with fpc) | Done |
| 1b | Peephole optimization (optional) | In progress |
| 1c | Language completeness polish | In progress |
| 2 | Embedding libraries (Rust, then C) | Rust working; C partial |
| 3 | Self-hosting | Done (fixpoint validated) |
| 4 | Browser playground | Done |
| 5 | Playground file I/O | Not started |
| 6 | Dynamic allocation (`New`/`Dispose`) | Not started |
| 6b | Richer string type | Not started |
| 7 | Units and separate compilation | Not started |
| 8 | Interfaces and methods | Not started |

## Documentation

| Document | Description |
|---|---|
| [EMBEDDING-GUIDE.md](EMBEDDING-GUIDE.md) | Embedding the compiler in a Rust application |
| [doc/compact-pascal-wp.md](doc/compact-pascal-wp.md) | White paper — motivation, architecture, grammar |
| [doc/compact-pascal-ref.md](doc/compact-pascal-ref.md) | Language reference (living document, CalVer versioned) |
| [doc/compact-pascal-tutorial.md](doc/compact-pascal-tutorial.md) | Compiler tutorial book — building the compiler step by step |
| [doc/pode-server.md](doc/pode-server.md) | Pode Server design (Pascal Node clone) |
| [doc/lightout-example.md](doc/lightout-example.md) | Light's Out browser game example design |
| [doc/playground.md](doc/playground.md) | Browser playground design |

## Prerequisites

### Required

- **Free Pascal Compiler (fpc)** — needed only for bootstrapping the compiler.

  ```bash
  # Debian/Ubuntu
  sudo apt install fp-compiler

  # macOS (Homebrew)
  brew install fpc

  # Arch Linux
  sudo pacman -S fpc
  ```

- **A WASM runtime** — for running the compiler and compiled programs.

  ```bash
  # wasmtime (recommended)
  curl https://wasmtime.dev/install.sh -sSf | bash
  ```

- **C compiler** (optional) — for building the C embedding library and examples.

  ```bash
  # Debian/Ubuntu
  sudo apt install build-essential
  ```

- **Rust** (stable, 1.85 or later) — for the embedding crate. Nothing else is
  needed to use it: the compiler snapshot is built into the crate, so a Rust
  user needs no Pascal toolchain and no WASM runtime of their own.

  ```bash
  cargo build
  cargo test
  cargo run --example hello
  ```

### Optional

- **Pandoc**, **Typst**, and **TeX Gyre fonts** — for generating PDF documentation.

  ```bash
  # Debian/Ubuntu
  sudo apt install pandoc fonts-texgyre
  cargo install typst-cli

  # Fedora
  sudo dnf install pandoc texlive-tex-gyre
  cargo install typst-cli

  # macOS (Homebrew)
  brew install pandoc typst
  brew install --cask font-tex-gyre-pagella font-tex-gyre-heros font-tex-gyre-cursor
  ```

  Then run:

  ```bash
  make pdf
  ```

## Project Layout

```
compiler/       — Pascal source for the compiler (cpas.pas, ~11.5k lines)
compiler-tests/ — test suite (108 positive, 19 negative, 5 command-line, shell runner)
src/
  c/            — C embedding library (compact_pascal.h/.c, vtable-based)
  rust/         — Rust crate source (compiler, runtime, WASI bridge)
snapshot/       — compiler WASM blob (compiler.wasm)
vendor/wasm3/   — wasm3 C source (used by C library)
examples/
  pascal/       — Compact Pascal example programs
  c/            — C embedding examples (hello, student-compiler)
doc/            — white paper, language reference, tutorial, tech notes
pages/          — GitHub Pages site
  playground/   — browser-based IDE (vanilla HTML/CSS/JS)
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to build, what the tests check,
and the two invariants a change must keep. Conduct expectations are in
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md); changes are recorded in
[CHANGELOG.md](CHANGELOG.md).

To report a security issue, see [SECURITY.md](SECURITY.md) rather than opening
an issue.

## License

[CC0 1.0 Universal](LICENSE). This project is dedicated to the public domain.

Use it for anything, commercially or otherwise. No attribution is required,
though it is welcome. There is no warranty.

Most of this codebase was written by a machine, and machine-written work
carries no copyright to assign. CC0 states plainly what is already the case
rather than claiming a right in order to license it back out.
