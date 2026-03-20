# SuperPascal

**Designer:** Per Brinch Hansen
**Released:** 1993
**Paradigm:** Concurrent, imperative, structured
**Influenced by:** CSP, Pascal, Concurrent Pascal, Joyce, occam
**Wikipedia:** https://en.wikipedia.org/wiki/SuperPascal
**Source:** http://pascal.hansotten.com/per-brinch-hansen/superpascal-compiler/

## Core Concept

SuperPascal is a **publication language** for parallel scientific computing — a thinking
tool for expressing parallel algorithms clearly and concisely. It extends a secure
subset of IEEE Standard Pascal with deterministic statements for parallel processes and
synchronous message communication. The parallel features are a subset of occam 2, with
the added generality of **dynamic process arrays** and **recursive parallel processes**.

Hansen's motivation came from three years of developing model parallel programs on
transputer networks: he concluded that parallel scientific algorithms could be developed
in an elegant publication language and tested on a sequential computer, then implemented
in a parallel runtime later.

## Security Through Restriction

SuperPascal deliberately omits features that are ambiguous or insecure:

- **No labels or `goto`**
- **No pointers**
- **No forward declarations**

These omissions enable a single-pass compiler to verify that parallel processes are
**disjoint** — they don't interfere with each other's variables — even when processes
use procedures with global variables.

### Disjointness Rule

Parallel processes can only update **disjoint sets of variables**. In a `parallel`
statement, a target variable cannot be updated by more than one process, but expression
variables (read-only) may be shared. When the programmer knows that array element
access is disjoint (e.g., each process works on a different index), a `[sic]` statement
overrides the restriction.

## Parallel Constructs

### `parallel` Statement

Executes a fixed number of statements concurrently:

```pascal
parallel
  source() |
  sink()
end
```

### `forall` Statement

Parallel execution with a dynamic number of processes:

```pascal
forall i := 0 to 10 do
  something()
end
```

### Typed Channels

Channel types specify what value types may be transmitted:

```pascal
type channel = *(boolean, integer);
var c: channel;
open(c);
```

Communication via `send` and `receive`:

```pascal
send(right, value + 1);
receive(left, value);
```

Both support multiple arguments:

```pascal
send(channel, e1, e2, ..., en);
receive(channel, v1, v2, ..., vn);
```

### Runtime Errors

- **Channel contention:** Two parallel processes both attempt to send or receive on
  the same channel simultaneously.
- **Message type error:** Sender and receiver use different types on the same channel.
- **Deadlock:** A send or receive waits indefinitely.

### Parallel Recursion

Recursive procedures combined with `parallel` and `forall` create dynamic process
topologies:

```pascal
procedure pipeline(min, max: integer; left, right: channel);
var middle: channel;
begin
  if min < max then
  begin
    open(middle);
    parallel
      node(min, left, middle) |
      pipeline(min + 1, max, middle, right)
    end
  end
  else node(min, left, right)
end;
```

Process trees:

```pascal
procedure tree(depth: integer; bottom: channel);
var left, right: channel;
begin
  if depth > 0 then
  begin
    open(left, right);
    parallel
      tree(depth - 1, left) |
      tree(depth - 1, right) |
      root(bottom, left, right)
    end
  end
  else leaf(bottom)
end;
```

## Implementation

The compiler and interpreter are written in sequential ISO Level 1 Pascal and can be
built with GNU Pascal or Free Pascal (2.7.1+ with `-Miso`). A modern fork by
Christopher Long compiles with current Free Pascal:
https://github.com/octonion/superpascal

## Significance

SuperPascal demonstrated that parallel programming could be expressed in a small,
clean, Pascal-based language — predating many modern approaches to safe concurrency.
The single-pass disjointness checking is particularly notable: it catches race
conditions at compile time without complex type systems.

## References

- P. Brinch Hansen, "SuperPascal — A Publication Language for Parallel Scientific
  Computing," *Concurrency: Practice and Experience*, vol. 6, no. 5, pp. 461–483, 1994.
- P. Brinch Hansen, "The Programming Language SuperPascal," *Software: Practice and
  Experience*, vol. 24, no. 5, pp. 399–406, 1994.
- Wikipedia: https://en.wikipedia.org/wiki/SuperPascal
- Brinch Hansen Archive: http://brinch-hansen.net/
