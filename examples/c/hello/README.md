# Running a Compact Pascal program from C

`main.c` runs a compiled `.wasm` module using [wasm3](https://github.com/wasm3/wasm3),
implementing the five WASI preview 1 functions a Compact Pascal program can
import. It is about 300 lines and it works.

**This is a reference sample, not a library.** The project shipped a C
embedding library for a while; it was removed, and the reasoning is in
`ROADMAP.md` under "Not planned". The short version: the library's design
required the host to supply its own WASM engine through a vtable, which is the
hard half of the job, so it saved a C user roughly what this file already
shows them.

It is not built by CI and it is not covered by tests. It is kept because it
answers the question a C user actually has, and because it was verified working
at the time it was written. If it has drifted, treat it as documentation of the
approach rather than as code to run unmodified.

## Building

You need wasm3 from upstream. There is no vendored copy in this repository.

```bash
git clone https://github.com/wasm3/wasm3 /tmp/wasm3
cc -std=c11 -O2 -I/tmp/wasm3/source -o hello main.c /tmp/wasm3/source/*.c -lm
```

## Running

Compile a Pascal program to WASM first, then run it:

```bash
wasmtime run ../../../snapshot/compiler.wasm < hello.pas > hello.wasm
./hello hello.wasm
```

## What it shows

The whole host-side contract is five WASI imports, and a program uses only the
ones it needs:

| Import | Needed when |
|---|---|
| `fd_write` | the program uses `write` or `writeln` |
| `fd_read` | the program uses `read` or `readln` |
| `proc_exit` | the program calls `halt` |
| `args_sizes_get`, `args_get` | the program reads command-line arguments |

A program that does no I/O and never calls `halt` imports nothing at all, and
needs no host support beyond instantiating it.

The exact signatures and the iovec layout are in the language reference under
"Implicit WASI Imports". Any WASM runtime with a C API will do; wasm3 is used
here because it is small and easy to embed.

## If you want the supported path

The Rust crate compiles Pascal at run time with the compiler snapshot built in,
so it needs no external toolchain and no separate runtime. See
[EMBEDDING-GUIDE.md](../../../EMBEDDING-GUIDE.md).
