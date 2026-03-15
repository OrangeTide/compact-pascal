# Compact Pascal

![Status: Early Development](https://img.shields.io/badge/status-early%20development-orange)
![License: MIT OR Apache-2.0](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue)
![WASM Target: 1.0 MVP](https://img.shields.io/badge/WASM-1.0%20MVP-purple)

An embeddable Pascal-to-WebAssembly compiler. The compiler is written in Pascal, compiles to WASM 1.0, and ships as a self-contained WASM binary. Embedding libraries for Rust and Zig let you compile and run Compact Pascal programs from your application — no external Pascal toolchain required.

## Overview

Compact Pascal is a new language in the Pascal family. It inherits Pascal's syntax and strong typing while making deliberate departures for embeddability:

- **No I/O runtime library** — `write`/`writeln`/`read`/`readln` are compiler intrinsics that lower to WASI host imports. No file types. Programs without I/O have zero implicit imports.
- **Minimal runtime** — the compiled WASM output has no standard library overhead. Host applications provide exactly the functionality they want.
- **Single-pass compiler** — fast compilation, especially important when the compiler itself runs inside a WASM interpreter.
- **WASM 1.0 MVP only** — no WASM extensions, maximum portability across runtimes.
- **Modern extensions** — structural interfaces with `implement` blocks (Go-style), short-circuit `and then`/`or else` (ISO 10206), and a macro system are planned.

### How It Works

```
+---------------------------------------------------+
|  Your Application (Rust / Zig / Browser JS)       |
+---------------------------------------------------+
|  Embedding Library (compact-pascal crate/module)   |
|  +----------------+   +-----------------------+   |
|  | WASM Runtime   |   | Host-Guest FFI        |   |
|  | (wasmi / wasm3)|   | (imports / exports)   |   |
|  +----------------+   +-----------------------+   |
+---------------------------------------------------+
|  Compiler (WASM blob, written in Pascal)           |
|  source -> [fd 0] -> compiler -> [fd 1] -> .wasm  |
+---------------------------------------------------+
|  Compiled Program (WASM module)                    |
|  executed by the same WASM runtime                 |
+---------------------------------------------------+
```

The compiler ships as a pre-compiled WASM binary embedded in the library. Your application feeds Pascal source in, gets a WASM module out, and runs it — all in-process.

### Quick Example (Rust)

```rust
let compiler = compact_pascal::Compiler::new();
let wasm_bytes = compiler.compile(pascal_source)?;

let mut runtime = compact_pascal::Runtime::new();
runtime.register_import("print_int", |val: i32| { println!("{val}"); })?;
let instance = runtime.instantiate(&wasm_bytes)?;
instance.call("main", &[])?;
```

### Quick Example (Zig)

```zig
const cp = @import("compact-pascal");

var compiler = cp.Compiler.init();
const wasm_bytes = try compiler.compile(pascal_source);

var runtime = cp.Runtime.init();
try runtime.registerImport("print_int", printInt);
var instance = try runtime.instantiate(wasm_bytes);
try instance.call("main", &.{});
```

## Status

**Early development.** The project is in the planning and design phase. No compiler or libraries exist yet. See the [project plan](PLAN.md) for the phased roadmap.

| Phase | Description | Status |
|---|---|---|
| 1 | Compiler (Pascal, bootstrapped with fpc) | Not started |
| 2 | Embedding libraries (Rust + Zig) | Not started |
| 3 | Self-hosting | Not started |
| 4 | Browser / WASM target | Not started |
| 5 | Dynamic allocation (`New`/`Dispose`) | Not started |
| 5b | Richer string type | Not started |
| 6 | Macro system | Not started |
| 7 | Interfaces and methods | Not started |

## Documentation

| Document | Description |
|---|---|
| [PLAN.md](PLAN.md) | Project plan with phased roadmap and findings |
| [doc/compact-pascal-wp.md](doc/compact-pascal-wp.md) | White paper — motivation, architecture, grammar |
| [doc/compact-pascal-ref.md](doc/compact-pascal-ref.md) | Language reference (living document, CalVer versioned) |

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

- **Rust** (stable) — for building the Rust embedding library.

  ```bash
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  ```

- **Zig** — for building the Zig embedding library.

  ```bash
  # See https://ziglang.org/download/
  # Or via package manager:
  # Debian/Ubuntu (via snap)
  sudo snap install zig --classic

  # macOS (Homebrew)
  brew install zig
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
compiler/       — Pascal source for the compiler (built with fpc)
compiler-tests/ — test suite (positive and negative tests)
src/            — Rust crate source
src-zig/        — Zig library source
snapshot/       — compiler WASM blob (shared by Rust and Zig)
examples/
  rust/         — Rust example programs
  zig/          — Zig example programs
doc/            — white paper and language reference
pages/          — GitHub Pages site
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

Licensed under either of

- [Apache License, Version 2.0](LICENSE-APACHE)
- [MIT License](LICENSE-MIT)

at your option.
