# Pascal-FC

**Designers:** Alan Burns and Geoff Davies (University of York)
**Released:** Early 1990s
**Paradigm:** Concurrent, imperative, structured
**Website:** https://www-users.york.ac.uk/~ab38/pf.html

## Core Concept

Pascal-FC (FC = "for Concurrency") is a teaching language that extends a simplified
Pascal with **multiple concurrency models** in a single language. Unlike Joyce or
SuperPascal, which each commit to one concurrency paradigm, Pascal-FC lets students
experiment with and compare semaphores, monitors, CSP-style channels, Ada-style
rendezvous, and Ada 95 protected types (resources) — all in the same language.

## Concurrency Primitives

Pascal-FC supports five distinct concurrency mechanisms:

| Mechanism | Origin | Key Operations |
|-----------|--------|----------------|
| Semaphores | Dijkstra | `wait`, `signal` |
| Monitors | Brinch Hansen/Hoare | Procedures with automatic mutual exclusion |
| Channels | CSP/occam | Synchronous send/receive |
| Remote invocation | Ada rendezvous | `accept` / `select` |
| Resources | Ada 95 protected types | Protected shared data |

This breadth makes Pascal-FC unique among Pascal dialects — it's a concurrency
taxonomy in language form.

## Process Declarations

Pascal-FC uses explicit process type declarations. Once a type is declared, specific
instances are declared in `var` declarations. The `cobegin`/`coend` structure expresses
concurrent execution.

## Random Process Switching

A distinctive implementation feature: the runtime system incorporates **random switching
between user processes**, providing an excellent simulation of true parallelism. This
approach invariably finds bugs in poorly structured programs that might pass under
deterministic scheduling — a valuable teaching tool.

## Significance

Pascal-FC's value is pedagogical rather than practical. By offering multiple concurrency
models side by side, it enables direct comparison of approaches to the same problem
(bounded buffer, dining philosophers, etc.) in a single language environment.

## References

- A. Burns and G.L. Davies, "Pascal-FC: A Language for Teaching Concurrent
  Programming," *ACM SIGPLAN Notices*, vol. 23, no. 9, 1988.
  https://doi.org/10.1145/44304.44309
- G.L. Davies, "Developments in Pascal-FC," *ACM SIGPLAN Notices*, 1989.
  https://dl.acm.org/doi/pdf/10.1145/71052.71062
- Pascal-FC homepage: https://www-users.york.ac.uk/~ab38/pf.html
- Pascal-FC User Guide: http://www.lcc.uma.es/~gallardo/pc_ug.pdf
