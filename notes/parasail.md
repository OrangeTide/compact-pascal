# ParaSail

**Designer:** S. Tucker Taft
**Developer:** AdaCore
**Released:** 2009
**Paradigm:** Object-oriented, concurrent, imperative, structured
**Influenced by:** Modula, Ada, Pascal, ML
**Influenced:** Nim
**Website:** https://parasail-lang.org/
**Wikipedia:** https://en.wikipedia.org/wiki/ParaSail_(programming_language)
**Paper:** https://arxiv.org/abs/1902.00525

## Core Concept

ParaSail (Parallel Specification and Implementation Language) is a pointer-free,
pervasively parallel language designed to make full, safe use of parallel hardware.
Its radical approach: **eliminate the features that make parallelism hard** rather than
adding features to manage it. No pointers, no global variables, no parameter aliasing,
no global garbage-collected heap, no explicit threads/locks/signals. The compiler
identifies parallelism automatically and detects race conditions at compile time.

## Pointer-Free Programming Model

ParaSail eliminates pointers entirely. Instead:

- **Value semantics** for assignment — objects are copied, not aliased.
- **Expandable/shrinkable objects** — objects can grow and shrink dynamically.
- **Optional components** — types can be recursive if recursive parts are `optional`.
- **Generalized indexing** — replaces pointer arithmetic and linked-list traversal.

This model eliminates dangling pointers, null pointer dereferences, and aliasing bugs
by construction.

## Region-Based Memory Management

Instead of a global garbage-collected heap, ParaSail uses **region-based storage
management**: memory is organized into regions that are reclaimed automatically and
immediately when they go out of scope. This provides:

- No GC pauses
- No global contention for heap allocation
- Deterministic reclamation
- Good cache locality

## Implicit Parallelism

**Every expression** in ParaSail has parallel evaluation semantics. Given `F(X) + G(Y)`,
the language guarantees it is safe to evaluate `F(X)` and `G(Y)` in parallel. The
compiler decides whether to create parallel activities based on expression complexity.

Additional parallel constructs:

```
// Concurrent loop
for each Elem of Nums concurrent loop
  Elem += 1
end loop

// Built-in parallel map-reduce
```

## Safety Constraints

| Eliminated Feature | Rationale |
|--------------------|-----------|
| Global variables | Operations access only their parameters |
| Parameter aliasing | Two updateable params can't reference same object |
| Pointers | Replaced by optional/expandable objects |
| Explicit threads/locks | Compiler identifies parallelism automatically |
| Runtime exceptions | Replaced by compile-time precondition checking |

## Assertions and Contracts

Hoare-style preconditions, postconditions, and invariants are part of the standard
syntax:

```
func Fib(N : Int) {N >= 0} -> Int
```

Module-level constraints (class invariants) apply across all operations.

## Module System

ParaSail has **parameterized modules** with full separation of interface from
implementation:

```
interface BMap<Key_Type is Ordered<>; Element_Type is Assignable<>> is
  op "[]"() -> BMap;
  func Insert(var BMap; Key : Key_Type; Value : Element_Type);
  func Find(BMap; Key : Key_Type) -> optional Element_Type;
  func Delete(var BMap; Key : Key_Type);
  func Count(BMap) -> Univ_Integer;
end interface BMap;

class BMap is
  ...
  exports
    op "[]"() -> BMap is ... end op "[]";
    func Insert(...) is ... end func Insert;
  ...
end class BMap;
```

Type parameters use **bounded generics** — `Key_Type is Ordered<>` means the key type
must implement the `Ordered` interface. This is similar to trait bounds.

## Move Semantics

Assignment in ParaSail is a **move**, not a copy. After `X := Y`, the variable `Y`
becomes `null` (its value has moved). This eliminates reference counting and shared
ownership. Explicit `Copy` is needed for actual duplication. Combined with the no-aliasing
rule, this means two variables can never refer to the same object.

## Concurrent Objects

Objects can be declared `concurrent`, making their operations implicitly thread-safe:

```
concurrent interface Shared_Counter<> is
    func Increment(locked var C : Shared_Counter);
    func Value(locked C : Shared_Counter) -> Integer;
end interface Shared_Counter;
```

The `locked` keyword indicates exclusive access — the runtime handles locking. This
is essentially a monitor pattern expressed through the type system, with no explicit
mutexes. Connects directly to Brinch Hansen's monitor concept but via the type system
rather than a special module kind.

## Work Stealing

ParaSail's light-weight threads are scheduled using a **work-stealing** approach that
provides load balancing across processors with good locality of reference and minimal
cache contention.

## Syntax

ParaSail's syntax is Modula-like with an `end` keyword closing each construct. It
resembles Ada more than Pascal in places (`:=` for assignment, `end func`, `end loop`).

```
func Hello_World(var IO) is
  IO.Println("Hello, World");
end func Hello_World;
```

## Dialects

The parallel constructs have been adapted to other syntactic bases:
- **Javallel** — Java-like syntax
- **Parython** — Python-like syntax
- **Sparkel** — Ada/SPARK-like syntax

All share the same compiler infrastructure.

## Relation to Pascal Family

ParaSail is categorized in the Pascal programming language family (per Wikipedia)
through its Modula/Ada lineage. The syntax, module system, and strong typing are
recognizably from the Wirth tradition, but the language goes much further in
eliminating unsafe features.

## References

- S. Tucker Taft, "ParaSail: A Pointer-Free Pervasively-Parallel Language for
  Irregular Computations," *Programming Journal*, vol. 3, no. 7, 2019.
  https://arxiv.org/abs/1902.00525
- ParaSail website: https://parasail-lang.org/
- AdaCore ParaSail page: https://adacore.github.io/ParaSail/
- Wikipedia: https://en.wikipedia.org/wiki/ParaSail_(programming_language)
- ParaSail blog: https://parasail-programming-language.blogspot.com/
