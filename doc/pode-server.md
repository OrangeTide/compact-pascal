# Pode Server: The Pascal Node Clone

**Pode** (rhymes with Node; also a word for toad) is a toy web server where Pascal programs handle HTTP requests. It is a playful parody of Node.js and Deno, demonstrating the Compact Pascal embedding library in a practical (and amusing) context.

Pode lives in `examples/rust/pode-server/` and uses the `compact-pascal` Rust crate with axum.

## Startup Banner

```
        _    _
       (o\  /o)
        \ \/ /
        _|  |_
       / |  | \
      /  |__|  \
          ||
         _||_

  🐸 Pode Server v0.1
     "The Pascal Node Clone"

  Runtime:     wasmi (WASM interpreter)
  Routes:      3 programs compiled (1,204 bytes total)
  Permissions: --allow-stdout --allow-stdin
  Listen:      http://localhost:3000

  It's like Node, but with begin...end.
```

## Core Concept

Drop `.pas` files in a `routes/` directory. Each file becomes an HTTP endpoint. The filename maps to the route path:

```
routes/
  hello.pas     → GET /hello
  fib.pas       → GET /fib
  greet.pas     → GET /greet
```

At startup, Pode compiles every `.pas` file in `routes/` to WASM using the Compact Pascal compiler. Each compiled module is cached in memory. On each HTTP request, Pode instantiates the matching WASM module, pipes input via stdin, and returns stdout as the HTTP response body.

## Request Handling

**Query string → stdin.** `GET /fib?input=10` pipes `"10\n"` to the program's `fd_read` (stdin). The Pascal program reads it with `readln(n)` like it's a terminal. No special HTTP library needed — the Pascal code is unaware it's serving web requests.

**stdout → HTTP response.** The program's `fd_write` (stdout) output becomes the response body. Content-Type defaults to `text/plain`.

**stderr → server console.** Stderr output appears in the server's terminal with a colored route prefix:

```
[hello]  Hello, World!
[fib]    Computing fibonacci(10)...
[fib]    ⚠ Warning: n > 40 may be slow
```

**Compilation errors** at startup are fatal — Pode refuses to start if any `.pas` file fails to compile. This keeps the error handling dead simple.

## Hot Reload

Pode watches the `routes/` directory for file changes (via the `notify` crate). When a `.pas` file is saved:

1. Recompile the changed file
2. Replace the cached WASM module
3. Print to the terminal: `Recompiled routes/fib.pas (247 bytes)`

If recompilation fails, keep the old module and print the error. The server stays up.

## Permissions (Deno Parody)

WASM sandboxing means Pascal code literally cannot do anything the host doesn't provide. Pode leans into this with Deno-style permission flags:

```
--allow-stdout    Allow programs to write output (default: on)
--allow-stdin     Allow programs to read input from query string
--allow-args      Allow programs to read command-line arguments
```

That's it. Three permissions. No filesystem, no network, no environment variables, no child processes. Print the active permissions at startup. The joke is that this is *actually the complete security model* — WASM sandboxing makes it real, not theater.

## Example Route: hello.pas

```pascal
program Hello;
begin
  writeln('Hello from Pode!');
end.
```

`GET /hello` → `Hello from Pode!`

## Example Route: fib.pas

```pascal
program Fibonacci;
var
  n, i: integer;
  a, b, tmp: integer;
begin
  readln(n);
  a := 0;
  b := 1;
  for i := 2 to n do
  begin
    tmp := a + b;
    a := b;
    b := tmp;
  end;
  writeln(b);
end.
```

`GET /fib?input=10` → `55`

## Example Route: greet.pas

```pascal
program Greet;
var
  name: string;
begin
  readln(name);
  if length(name) = 0 then
    name := 'World';
  writeln('Hello, ', name, '!');
end.
```

`GET /greet?input=Jon` → `Hello, Jon!`

## Implementation Notes

**Target size:** ~150 lines of Rust, plus the example `.pas` files. Dependencies: `compact-pascal`, `axum`, `tokio`, `notify`, `clap` (for the permission flags).

**Why this is actually interesting beyond the joke:**
- Each request runs in a fresh WASM instance — true per-request isolation with no shared mutable state
- A misbehaving program can't crash the server (WASM traps are caught)
- Compilation happens once at startup (or on hot reload), so request latency is just WASM instantiation + execution
- The Pascal programs are portable — the same `.pas` files run under `wasmtime`, in the browser playground, or embedded in any host

## Landing Page

`GET /` serves a minimal HTML page listing all routes with links. Each link includes an input field if the route's `.pas` source contains `readln`. The page is generated from the route table — no static HTML file needed.
