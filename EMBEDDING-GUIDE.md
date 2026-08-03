# Embedding Compact Pascal in Rust

This guide covers the `compact-pascal` crate: compiling Pascal source at run
time, running the result, passing values across the boundary, and reading the
compiler's diagnostics.

The compiler ships as a WebAssembly module compiled into the crate. Nothing is
read from disk, no Pascal toolchain is needed at build or run time, and the
compiled program runs in the same sandbox as the compiler.

## Contents

- [The shortest useful program](#the-shortest-useful-program)
- [Compiling](#compiling)
- [Diagnostics](#diagnostics)
- [Running](#running)
- [Calling into Pascal](#calling-into-pascal)
- [Calling back into the host](#calling-back-into-the-host)
- [Strings across the boundary](#strings-across-the-boundary)
- [Include files](#include-files)
- [What the sandbox does and does not protect](#what-the-sandbox-does-and-does-not-protect)
- [API stability](#api-stability)

## The shortest useful program

```rust
use compact_pascal::{Compiler, Instance};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let result = Compiler::new()
        .compile("program Hello; begin writeln('Hello!') end.")?;
    Instance::new(&result.wasm)?.run()?;
    Ok(())
}
```

Three working examples live in `examples/rust`. Run them with
`cargo run --example hello`, `--example calculator`, and
`--example host-callback`. They are covered by the test suite, so they are
kept working rather than left to rot.

## Compiling

`Compiler::compile` takes source and returns a `CompileResult` holding the WASM
module, the compiler's raw stderr, and the parsed diagnostics.

```rust
let result = Compiler::new().compile(source)?;
println!("{} bytes of WASM", result.wasm.len());
```

### Options

`Options` carries the same switches the `cpas` command line takes. The defaults
match the compiler's own, so `Options::default()` compiles exactly as the
command-line compiler does with no arguments.

```rust
use compact_pascal::{Compiler, Options};

let compiler = Compiler::with_options(Options {
    range_checks: true,               // {$R+}: check array and subrange bounds
    stack_checks: true,               // {$S+}: stack, frame, and nil checks (default)
    defines: vec!["DEBUG".to_string()], // -dDEBUG, visible to {$IFDEF DEBUG}
    verbose: false,                   // -v: emit Info: diagnostics
});
```

A directive in the source still overrides these from the point it appears.
`Options` sets what the file starts with.

**Turning `stack_checks` off is a real decision, not a tuning knob.** With it
on, a stack overflow, an unbalanced frame, and a nil dereference each trap at
the point they happen. With it off, all three corrupt memory quietly and the
symptom appears somewhere unrelated. Leave it on unless you are compiling
source you wrote and have measured the cost.

## Diagnostics

The compiler tags every line it writes to stderr, which is what makes the
output parseable rather than guessed at:

```
Error: 12:5: unknown identifier: FOO
Warning: unreachable code after halt
Info: stack size 65536
```

`Diagnostic` takes those apart into a severity, an optional line and column,
and a message.

### A failed compilation

```rust
match Compiler::new().compile(source) {
    Ok(result) => { /* use result.wasm */ }
    Err(e) => {
        if let Some(d) = e.first_error() {
            match (d.line, d.column) {
                (Some(l), Some(c)) => eprintln!("line {l}, column {c}: {}", d.message),
                _ => eprintln!("{}", d.message),
            }
        } else {
            eprintln!("{e}");
        }
    }
}
```

`CompileError` distinguishes four situations, and the distinction matters when
deciding whether to blame the program or the tooling:

| Variant | Meaning | Whose fault |
|---|---|---|
| `Rejected` | The compiler read the program and refused it. Carries diagnostics. | The Pascal source |
| `Exit` | The compiler exited nonzero without a parseable diagnostic. | A bug; please report it |
| `Instantiation` | The snapshot could not be loaded or started, or it trapped. | A bug; please report it |
| `Include` | An `{$I 'file'}` could not be resolved. | The host's include paths |

### A successful compilation with warnings

Warnings do not stop a compilation. Whether to treat them as fatal is the
host's call:

```rust
let result = Compiler::new().compile(source)?;
let warnings: Vec<_> = result.warnings().collect();
if !warnings.is_empty() && strict {
    return Err(format!("{} warnings, refusing to run", warnings.len()).into());
}
```

## Running

`Instance::new` instantiates a compiled module. It does not run it: a compiled
program has no WASM start section, so nothing executes until you ask. `run`
calls the `_start` export, which is the program's top-level `begin...end.`
block.

```rust
let mut instance = Instance::new(&result.wasm)?;
instance.run()?;
```

The gap between the two is useful. Between instantiating and running you can
write into the guest's memory, and after running you can read out of it.

### Reading the failure

`RuntimeError` separates the ways a program can stop:

| Variant | Meaning |
|---|---|
| `Exit(n)` | The program called `halt(n)`. An ordinary ending, not a fault. |
| `Trapped(msg)` | The program trapped. |
| `FunctionNotFound(name)` | No export by that name. |
| `Instantiation(msg)` | The module could not be loaded, or an import was not registered. |
| `Memory(msg)` | A memory access through this API failed. Raised by the string helpers below, never by execution. |

`halt(0)` is success and returns `Ok(())`.

```rust
match instance.run() {
    Ok(()) => {}
    Err(e) => match e.exit_status() {
        Some(n) => println!("program asked to exit with {n}"),
        None => eprintln!("{e}"),
    },
}
```

A trap reported as `unreachable` is usually a check firing rather than a
malformed module: the stack overflow guard, the frame balance check, and the
nil check all raise it. Division by zero and an out-of-range index under
`{$R+}` also trap.

## Calling into Pascal

`{$EXPORT name}` puts the next routine in the module's export table. Without
it, the routine exists but cannot be reached from the host.

```pascal
{$EXPORT evaluate}
function Evaluate(a, b: integer): integer;
begin
  Evaluate := a * a + b * b;
end;
```

```rust
let answer = instance.call_args("evaluate", &[3, 4])?; // Some(25)
```

`call_args` passes and returns 32-bit integers, which is every ordinal type the
language has: `integer`, `boolean`, `char`, enumerated types, and subranges are
all `i32`. A structured value crosses as an address into linear memory; see the
next section.

`call` runs an exported procedure that takes no arguments and returns nothing.

## Calling back into the host

The other direction. `{$IMPORT 'module' name}` declares that a routine comes
from outside, and `external` marks it as having no body:

```pascal
{$IMPORT 'host' readSensor}
function ReadSensor(id: integer): integer; external;

{$IMPORT 'host' recordReading}
procedure RecordReading(id, value: integer); external;
```

The host satisfies them before instantiating:

```rust
use compact_pascal::InstanceBuilder;

let mut builder = InstanceBuilder::new()?;

// (module, name, parameter count, returns a value, closure)
builder.register_import("host", "readSensor", 1, true, |args| {
    Some(read_hardware(args[0]))
})?;

builder.register_import("host", "recordReading", 2, false, move |args| {
    log.push((args[0], args[1]));
    None
})?;

let mut instance = builder.build(&result.wasm)?;
instance.call("poll")?;
```

Every import must be registered before `build`, and the signature must match
what the Pascal source declared. A mismatch fails at instantiation with a
message naming the import, not at the first call.

The closure is `Fn(&[i32]) -> Option<i32>` and must be `Send + Sync + 'static`.
Capture host state behind `Arc` and an atomic or a lock, as the
`host-callback` example does.

**This is the whole trust boundary.** A compiled program can do exactly what
the imports you register let it do, and nothing else. Registering a callback
that opens a file by name hands file access to the guest.

## Strings across the boundary

Compact Pascal strings are Turbo Pascal short strings: a length byte followed
by up to 255 bytes of data. They are not NUL-terminated and they are bytes
rather than characters, so UTF-8 content is stored verbatim and `length`
returns the byte count.

```rust
// Write into the guest's memory at a known address.
instance.write_pascal_string(addr, "hello")?;

// Read back. Validates UTF-8.
let s = instance.read_pascal_string(addr)?;

// Read back without validating, for content that is not UTF-8.
let bytes = instance.read_pascal_bytes(addr)?;
```

Both check bounds against the guest's memory and refuse a string longer than
255 bytes. Getting the address is the caller's problem: export a global from
the Pascal side, or pass a buffer address as an argument to an exported
routine.

## Include files

The compiler never sees `{$I 'file'}`. It has no filesystem, by design. The
host resolves includes before compilation:

```rust
use std::path::Path;

let result = Compiler::new()
    .compile_with_includes(source, Path::new("./pascal"))?;
```

`expand_includes` is also public if you want to do the expansion yourself,
inspect the result, or resolve names against something other than a directory.

Include expansion is where a host decides what the guest may read, so the base
directory is enforced as a boundary rather than used as a starting point. An
include path containing `..`, an absolute path, or a Windows drive prefix is
refused. Without that, `{$I '/etc/passwd'}` would work: joining an absolute
path onto a base discards the base.

The check is on the written path and does not touch the filesystem, so a
symlink inside the base directory that points outside it is still followed.
Do not place one there in a directory you serve untrusted source from.

## What the sandbox does and does not protect

Compiled programs run in a WebAssembly sandbox. That is a real boundary, and
it is narrower than it sounds.

**It does protect the host from the guest's memory.** A Pascal program cannot
read or write host memory, cannot reach the filesystem or the network, and
cannot see any capability that was not registered as an import. A guest bug
corrupts the guest's own linear memory and nothing else.

**It does not protect the guest from itself.** Within its own memory, a Pascal
program can corrupt its own data through a stale pointer or an out-of-range
index. The `{$S+}` and `{$R+}` checks exist for this and are worth their cost.

**It does not bound time or memory by default.** A guest program can loop
forever or grow memory until the host runs out. `Limits` puts a ceiling on
both:

```rust
use compact_pascal::{InstanceBuilder, Limits};

let builder = InstanceBuilder::with_limits(Limits {
    fuel: Some(50_000_000),              // roughly one unit per instruction
    memory_bytes: Some(16 * 1024 * 1024),
})?;
let mut instance = builder.build(&result.wasm)?;
```

Exhausting fuel is a trap, so it arrives as `RuntimeError::Trapped`. Fuel
metering costs some speed, so it is off unless you ask for it. A Pascal
program's own `{$MAXMEMORY}` is a second ceiling, and the lower of the two
wins.

**Compiling is running.** The compiler is itself a WASM program that executes
while it compiles. Compiling hostile source is as safe as running hostile
source in the same sandbox, and no safer.

## API stability

The crate follows semantic versioning once it reaches 1.0. Until then, minor
versions may break.

**Stable after 1.0**, meaning a change requires a major version:

- The names, signatures, and behavior of `Compiler`, `CompileResult`,
  `CompileError`, `Instance`, `InstanceBuilder`, `RuntimeError`, `Diagnostic`,
  `Severity`, `Options`, and `Limits`.
- The meaning of each `CompileError` and `RuntimeError` variant.
- The diagnostic tag format the compiler emits, since it is what `Diagnostic`
  parses.

**Not stable**, and may change in any release:

- The exact wording of diagnostic messages. Match on `severity`, `line`, and
  `column`; do not match on message text.
- The bytes of the compiled WASM module. Two versions may compile the same
  source to different modules.
- The contents of the compiler snapshot.
- Anything not re-exported from `lib.rs`.

New enum variants may be added in a minor version, so match with a `_` arm.

The language itself versions separately, on CalVer, and is described in the
[language reference](doc/compact-pascal-ref.md). See `ROADMAP.md` for what
"1.0" is meant to mean for the project as a whole.
