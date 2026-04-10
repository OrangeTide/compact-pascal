# Proposals for Extending Compact Pascal

## Operator Overloading - from Vector Pascal

  1. Operator overloading with identity elements — already mentioned in the white paper afterword as a possible future extension. Vector Pascal's design is the cleanest version I've seen: you specify three things — (symbol, function, identity element) — and you get unary operators and reductions for free. Unary -x becomes zero - x, unary /x becomes one / x. It's single-pass friendly (just symbol table dispatch), and the identity element trick means user-defined types automatically participate in any future reduction or broadcasting system.

  ```
  operator + = complex_add, complexzero;
  operator * = complex_multiply, complexone;
  ```

  This fits Compact Pascal's character — small mechanism, large payoff.

## Dimensioned Types - from Vector Pascal

  2. Dimensional types — compile-time unit checking with zero runtime cost. Dimension exponents are tracked in the type system; meter * meter produces meter^2, and adding meter + second is a compile-time error. Single-pass compatible — you just carry exponent vectors alongside the base type. The catch: it only makes sense once real is available (Phase 5+), so it's a later addition. But it's independently interesting as a safety mechanism for scientific/engineering code.

  Open question: how should we handle compound type casts. Such as converting between meters and feet?

  ```
  type
    Feet = real of distance;
    Meters = real of distance;
  const
    FeetToMeters = Feet (3.28084) / Meters (1);
  ```

  Or perhaps a more exotic type cast to avoid forcing the evaluation of types in the constant parser?

  ```
  const
    FeetToMeters = (Feet, Meters POW -1) (3.28084);
  ```

  or, as short-hand (but less general):

  ```
  const
    FeetToMeters = (Feet, /Meters) (3.28084);
  ```

## Annotations and Reflection - from Go, Rust, Java, etc.

  3. Needs more research. But records, types, variables, arrays, functions, etc could be tagged with annotation syntax. either back-tick (\`) like in Go annotations. or [[ ]] C++ attributes, or #[] in Rust attributes.

  The purpose of annotations would be to give libraries/units a way to do introspection and reflection.
  Perhaps reflect (the ability to modify itself, like in Lisp) is beyond the scope of Compact Pascal, although it might be an easier route towards macros than Rust's macros.

  Some example use cases would be to provide serializers for JSON to know which fields of a Record to import/export and under what name (primary use case in Go)

  A more exotic case would fit in the with next section on persistence.

## Persistence via Host Imports - From PS-algol

  4. Persistence via host imports — this is the most architecturally interesting match. PS-algol's core insight is
  that persistence should be orthogonal to the language — you write normal code, and the runtime decides what persists based on reachability from a root. Compact Pascal's WASM import model is a natural fit:
  - Host provides open_database, get_root, set_root, commit as WASM imports
  - The compiler (or a runtime library) handles serialization of records/arrays to/from a host-managed store
  - Persistence is identified by reachability from the root, same as PS-algol

  This doesn't require language changes — it's just host imports + a serialization convention. But the PS-algol
  papers show that doing it well (the PIDLAM, the threshing algorithm, transaction semantics) requires careful
  design. The 3x code reduction they measured vs. explicit database calls is the real selling point.

  The constraint: this needs New/Dispose and heap allocation (Phase 5) since persistent data structures are
  typically heap-allocated graphs. It also needs some form of GC or at least reachability analysis to decide what
  persists.

  Note: PS-algol's transaction model — commit/abandon with automatic threshing is elegant but the O(N²) threshing
  algorithm and the heap purge-to-database fallback are complex runtime machinery that conflicts with Compact
  Pascal's "minimal runtime" goal.

## Associative Tables as built-in abstractions - from PS-algol

  5. Associative tables as a built-in abstraction — PS-algol provides table, lookup(table, key), enter(table,value, key), scan(table, func) as standard functions backed by B-trees. In Compact Pascal, this could be a host-provided data structure via imports — the host maintains the B-tree, Pascal code just calls lookup/enter.  Useful as a standard library pattern even without persistence.

  Also of interest is Lua's associative tables and meta-tables. A subset of this might prove to be useful, if it can be mapped to a static language like Compact Pascal.
