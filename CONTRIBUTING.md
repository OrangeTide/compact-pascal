# Contributing to Compact Pascal

Thank you for your interest in contributing! This document explains how to get involved.

## Getting Started

1. Fork the repository at https://github.com/OrangeTide/compact-pascal
2. Clone your fork and create a branch for your work
3. Make your changes
4. Submit a pull request

## Development Prerequisites

See the [README](README.md) for installation instructions. You will need:

- **fpc** (Free Pascal Compiler) for working on the compiler
- **Rust** (stable) for the Rust embedding library
- **Zig** for the Zig embedding library
- **Pandoc + Typst** (optional) for building PDF documentation

## Building

```bash
# Bootstrap the compiler (requires fpc)
cd compiler && fpc -Mtp compact_pascal.pas

# Build the Rust library
cargo build

# Build the Zig library
zig build

# Generate PDF documentation
make pdf
```

## Running Tests

```bash
# Run compiler test suite
# (test runner TBD)

# Run Rust tests
cargo test

# Run Zig tests
zig build test
```

## Project Structure

- `compiler/` — Pascal compiler source. Changes here affect the core language.
- `compiler-tests/` — Compiler test suite (positive and negative tests).
- `src/` — Rust embedding library.
- `src-zig/` — Zig embedding library.
- `doc/` — Language specification.
- `snapshot/` — Compiler WASM blob. Do not edit directly; regenerated from compiler source.

## Guidelines

- Keep pull requests focused on a single change.
- Add tests for new compiler features (both positive and negative cases).
- Follow the existing code style in whichever language you are working in.
- Update `doc/compact-pascal.md` if your change affects the language specification.
- Update `PLAN.md` if your change completes a phase checklist item.

## Reporting Issues

Use [GitHub Issues](https://github.com/OrangeTide/compact-pascal/issues) to report bugs or suggest features. Please include:

- What you expected to happen
- What actually happened
- Steps to reproduce (ideally a minimal Compact Pascal program)

## License

By contributing, you agree that your contributions will be licensed under the same dual license as the project: MIT OR Apache-2.0.
