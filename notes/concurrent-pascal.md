# Concurrent Pascal

**Designer:** Per Brinch Hansen
**Released:** 1974
**Platform:** DEC PDP-11
**Wikipedia:** https://en.wikipedia.org/wiki/Concurrent_Pascal

## Core Concept

Concurrent Pascal is a programming language for writing concurrent programs such as
operating systems and real-time monitoring systems on shared-memory computers. It
extends Pascal with three new structured types — **classes**, **monitors**, and
**processes** — that make concurrency a first-class language concept rather than a
library concern.

The key insight is that **monitors** encapsulate shared data with the procedures that
access it, providing automatic mutual exclusion. This eliminates the error-prone manual
locking patterns of semaphore-based programming.

## Language Design

### Security Through Restriction

Concurrent Pascal removes several Pascal features to guarantee memory safety and prevent
inter-process interference:

- No variant records
- No `goto` statements and labels
- No procedures as parameters
- No packed arrays
- No pointer types
- No file types or standard I/O procedures

These omissions allow compile-time and minimal runtime checking to guarantee that a
program cannot address outside its allocated space.

### Three Structured Types

**Class:** Packages private variables and procedures with public "procedure entries."
A class instance can be used by only one process.

**Monitor:** Like a class but designed for shared access. Only one process can execute
within a given monitor instance at a time. Monitors are the *only* mechanism for
inter-process communication.

**Process:** Has local variables, procedures, and an initial statement that "ordinarily
executes forever." Processes communicate exclusively through monitor procedures.

### Queue-Based Scheduling

Monitors use a built-in `queue` type with `delay` and `continue` operations for
scheduling:

```pascal
procedure entry put(item: Integer);
begin
  if full then
    delay(fullq);      { block if full }
  saved := item;
  full := true;
  continue(emptyq)     { unblock consumer }
end;
```

Each queue variable holds at most one process. For multiple waiters, arrays of queues
are used. This gives monitors full control over scheduling but requires the programmer
to explicitly unblock the correct process.

### Static Configuration

The configuration of processes, monitors, and classes is established at program start
via `init` statements and is not changed thereafter. Communication paths are set up
through variables passed in `init` — class and monitor instances cannot be passed as
procedure parameters.

### Monitor Hierarchy

Language rules prevent deadlock by imposing a hierarchy on monitors. However, a monitor
can still effectively hang the system by failing to call `continue` on a delayed process.

## Influence

Concurrent Pascal's monitor concept became one of the foundational ideas in concurrent
programming, influencing:

- Java's `synchronized` keyword and monitor-based threading
- Ada's protected objects
- Brinch Hansen's later languages: Joyce and SuperPascal
- IP Pascal/Pascaline's monitor modules
- Pascal-FC's monitor construct

## References

- P. Brinch Hansen, "The Programming Language Concurrent Pascal," *IEEE Transactions
  on Software Engineering*, vol. 1, no. 2, pp. 199–207, June 1975.
  http://brinch-hansen.net/papers/1975a.pdf
- P. Brinch Hansen, *The Architecture of Concurrent Programs*, Prentice Hall, 1977.
- Wikipedia: https://en.wikipedia.org/wiki/Concurrent_Pascal
