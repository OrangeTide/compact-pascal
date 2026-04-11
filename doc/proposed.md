# Proposals for Extending Compact Pascal

## 1: Operator Overloading - from Vector Pascal

  Operator overloading with identity elements — already mentioned in the white paper as a possible future extension. Vector Pascal's design is the cleanest version I've seen: you specify three things — (symbol, function, identity element) — and you get unary operators and reductions for free. Unary -x becomes zero - x, unary /x becomes one / x. It's single-pass friendly (just symbol table dispatch), and the identity element trick means user-defined types automatically participate in any future reduction or broadcasting system.

  ```
  operator + = complex_add, complexzero;
  operator * = complex_multiply, complexone;
  ```

  This fits Compact Pascal's character — small mechanism, large payoff.

  **Resolution order:** Vector Pascal resolves predefined operators first, then searches user-defined overloads. This is single-pass friendly — the compiler never needs to defer resolution. The operator declaration just adds an entry to the symbol table, and lookup checks built-in operators before user-defined ones.

  **What you get without arrays:** Even without array types, the identity element gives you unary operators on user-defined types for free. `-x` on a complex becomes `complexzero - x`, `/x` becomes `complexone / x`. That alone justifies the mechanism. Other Pascal dialects (Zonnon, Active Oberon, Delphi) have operator overloading but without the identity element — you have to define unary and binary operators separately, which is more surface area for the same result.

  **What you get with arrays:** If arrays are ever first-class (element-wise operations, broadcasting), the identity element also powers reductions: `+y` sums the elements of `y` using `0` as the starting accumulator, `*y` takes the product using `1`. User-defined types with overloaded operators would get reductions for free — `+` on an array of complex values would reduce using `complexzero`. This is the full Vector Pascal payoff.

  **The minimalism question — arrays:** The full Vector Pascal array system (maps, reductions, iota, slicing, permutations, broadcasting) is a large feature. But a useful subset might be small:

  - *Level 0:* Operator overloading with identity elements, no array changes. Immediate value, minimal effort.
  - *Level 1:* Element-wise operations on arrays of types with overloaded operators. The compiler already knows the operator and the element type — applying it across an array is a loop. This is a code generation concern, not a language grammar change.
  - *Level 2:* Unary reduction (`+a` sums array `a`). Falls out of Level 1 plus the identity element. One new code generation pattern.
  - *Level 3:* Scalar broadcasting (`a * 3` multiplies every element by 3). Requires rank-matching rules in the type checker. This is where real complexity enters.

  Levels 0–2 are small mechanisms. Level 3 and beyond (slicing, iota, permutations) are where Vector Pascal's complexity lives. The question is whether Levels 1–2 are useful enough without Level 3 to justify the effort.

## 2: Dimensioned Types - from Vector Pascal

  Dimensional types — compile-time unit checking with zero runtime cost. Dimension exponents are tracked in the type system; meter * meter produces meter^2, and adding meter + second is a compile-time error. Single-pass compatible — you just carry exponent vectors alongside the base type. The catch: it only makes sense once real is available (Phase 5+), so it's a later addition. But it's independently interesting as a safety mechanism for scientific/engineering code.

  **These are two separate problems.** Vector Pascal's dimensional types handle dimensional analysis — preventing you from adding meters to seconds. They do *not* handle unit conversion — converting meters to feet. Both are the same dimension (`distance`), so the type system treats them identically. Separating these clarifies the design:

  ### 2a: Dimensional Analysis (from Vector Pascal, well understood)

  Vector Pascal uses an enum as the basis space. We propose a different approach that fits Pascal's existing idioms more naturally: **dimensions as a type classification**, using syntax analogous to variant records with dot notation.

  A dimension declaration looks like an enum, but it is not instantiable — you cannot declare a variable of the dimension type itself. Like a variant record's tag, you must select a case to get something concrete. The dimension exists only in the type system as a compile-time classification that groups related unit types.

  ```
  type
    dimension = (distance, mass, time);
  ```

  This declares three dimension cases. Concrete unit types are declared as `real of` a qualified dimension case, using the dot notation already present in the language from Go-style methods:

  ```
  { MKS (SI) unit system — all in one program, no imports needed }
  type
    dimension = (distance, mass, time);
    Meter = real of dimension.distance;
    Kilogram = real of dimension.mass;
    Second = real of dimension.time;
    Newton = real of dimension.mass * dimension.distance * dimension.time POW -2;
    MeterPerSecond = real of dimension.distance * dimension.time POW -1;
    Joule = real of dimension.mass * dimension.distance POW 2 * dimension.time POW -2;
  ```

  A student can put this in a single program and start experimenting immediately — no unit libraries required:

  ```
  program physics;
  type
    dimension = (distance, mass, time);
    Meter = real of dimension.distance;
    Second = real of dimension.time;
    MeterPerSecond = real of dimension.distance * dimension.time POW -1;
  var
    d: Meter;
    t: Second;
    v: MeterPerSecond;
  begin
    d := Meter(100.0);
    t := Second(9.58);
    v := d / t;               { type checks: distance / time = distance * time^-1 }
    writeln(v);
    { v := d + t; }           { compile error: distance + time is meaningless }
  end.
  ```

  Multiple unit systems define their own concrete types over the same dimension cases. The types are fully distinct — you cannot assign a `Meter` to a `USFoot` or add a `Kilogram` to a `USPound` without explicit conversion. But the compiler knows that `Meter` and `USFoot` are both `real of dimension.distance`, so a ratio type `Meter / USFoot` is dimensionally valid (the `distance` exponents cancel). A ratio type `Meter / USPound` would be `distance * mass POW -1` — not dimensionless, so it cannot be used as a simple conversion factor. The dimension case is the path that connects related units across systems.

  ```
  { CGS (centimetre-gram-second) — same dimension, different units }
  type
    Centimeter = real of dimension.distance;
    Gram = real of dimension.mass;
    Dyne = real of dimension.mass * dimension.distance * dimension.time POW -2;
    Erg = real of dimension.mass * dimension.distance POW 2 * dimension.time POW -2;
  ```

  ```
  { US Customary / FPS (foot-pound-second) }
  type
    USFoot = real of dimension.distance;
    USPound = real of dimension.mass;        { avoirdupois pound-mass }
    USSecond = real of dimension.time;       { same as SI second }
    PoundForce = real of dimension.mass * dimension.distance * dimension.time POW -2;
    USGallon = real of dimension.distance POW 3;  { volume as length^3 }
  ```

  **The variant record analogy and where it breaks down.** In a variant record, two variables with the same tag value are the same variant and freely assignable. Here, `Meter` and `USFoot` share a dimension case (`dimension.distance`) but are *not* assignable to each other. The case establishes dimensional compatibility — it lets the compiler verify that a conversion ratio between them is valid — but not type equivalence. This is closer to "these types share the same classification" than "these are the same variant." The analogy holds for the syntax and the "must select a case" constraint; it diverges on assignability.

  **Advantage over Vector Pascal's enum approach.** Vector Pascal would require either a shared enum (which conflates unit identity with dimensional identity) or separate enums per system (which prevents the compiler from reasoning about cross-system relationships). The dimension-as-classification approach gives both: shared dimensional reasoning and distinct unit types, using syntax that already feels like Pascal.

  **Independent dimension types.** Dimension declarations are independent of each other. A library for electromagnetic units would declare its own:

  ```
  type
    electrical = (charge, current, potential);
    Coulomb = real of electrical.charge;
    Ampere = real of electrical.current;
    Volt = real of electrical.potential;
  ```

  No global registry of dimensions, no conflict between unit libraries that don't know about each other.

  Note: we define US Customary units specifically, not "imperial." British imperial and US customary systems diverge in volume measures (US gallon ≠ imperial gallon, US pint ≠ imperial pint) and some weight measures. The identifiers and library names should make clear these are US units. A British imperial units library is out of scope but could be a student exercise — defining the conversions between US and imperial pints would require exactly the mechanisms described in 2b.

  **Deduction rules:** `*` and `/` add/subtract exponent vectors, `+` and `-` require matching exponents. `POW` between a dimensioned type and an integer literal multiplies all exponents. This is entirely compile-time — the generated code is identical to plain `real` arithmetic.

  Other metric systems of potential interest: **MTS** (metre-tonne-second, used in France and the USSR until the 1950s) defines force in sthènes and pressure in pièzes. **CGS** (centimetre-gram-second) is still used in some physics subfields. These are niche but demonstrate that the system is general — any coherent set of base units over the same dimensions works.

  **Real-world bugs this catches.** The Mars Climate Orbiter was lost in 1999 because Lockheed Martin's ground software produced thrust values in pound-force seconds while NASA's navigation code expected newton seconds. With dimensioned types, `PoundForce * USSecond` and `Newton * Second` are completely different types — assignment between them is a compile error. The Gimli Glider incident (1983, Air Canada Flight 143) involved a kg-to-pounds conversion error during refueling. These are cases where the program compiled and ran, but the numbers meant different things on each side of an interface.

  ### 2b: Unit Conversion (ratio-only, open design question)

  Conversion between units of the same dimension (meters ↔ feet, kilograms ↔ pounds) is a separate mechanism. Vector Pascal does not address this. Because each unit system defines completely distinct types, you cannot accidentally mix MKS and US Customary values — but you need a way to convert between them intentionally.

  The idea: conversion factors are typed constants with compound dimensions. Applying a conversion is ordinary multiplication, and the type checker verifies the dimensions cancel correctly. No special conversion syntax or runtime machinery is needed — just the existing dimensional deduction rules applied to constants.

  ```
  program demo;
  uses USCustomary, MKSUnits, USToMKS;

  const
    yardStickLength = USFoot(3);

  var
    length: Meter;

  begin
    { measure my house with a yard stick, and convert to meters }
    length := USFootToMeter * (12 * yardStickLength);
    writeln(length);
  end.
  ```

  Where the conversion unit would define:

  ```
  { USToMKS — exact conversion ratios, US Customary to MKS (SI) }
  { All ratios are exact by definition (US units are defined in terms of SI) }
  const
    USFootToMeter: Meter / USFoot = 0.3048;           { exact }
    USPoundToKilogram: Kilogram / USPound = 0.45359237; { exact }
    { USSecond = Second, no conversion needed }
  ```

  The type of `USFootToMeter` is a ratio type: `Meter / USFoot`. When the compiler sees `USFootToMeter * someUSFoot`, the `USFoot` in the numerator and denominator cancel, leaving `Meter`. This is just the normal dimensional exponent arithmetic — no special conversion mechanism.

  US Customary units have exact metric definitions by law (since the Mendenhall Order of 1893, formalized in 1959). This means conversion constants are exact rational numbers, not approximations. The international foot is exactly 0.3048 meters. The avoirdupois pound is exactly 0.45359237 kilograms. These constants can be represented exactly in the source; whether the floating point representation introduces error is a separate concern.

  **Ratio-only restriction:** This model intentionally excludes offset-based conversions like Fahrenheit ↔ Celsius, for the same reason GNU `units` does not support them directly — offset conversions are not multiplicative. `0 °F × 2 ≠ 0 °F` in any meaningful sense, and a conversion factor that requires addition breaks the property that conversion is just multiplication by a constant. Temperature-like conversions would need a function (`CelsiusToFahrenheit(x)`), which is a different mechanism and does not benefit from compile-time dimensional checking in the same way.

  **Open questions:**

  - Syntax for declaring the type of a conversion constant (`Meter / USFoot` as a type expression, or the `POW -1` form, or something else).
  - How unit libraries are organized — one unit per file, one system per file, or a hierarchy (dimensions, base units, derived units, conversion constants as separate units)?
  - Whether the compiler needs a concept of "canonical" unit system for a given dimension, or whether all systems are peers and conversion is always explicit.

  **The type-safety story:** The same system that prevents `Meter + Second` (2a) also ensures your conversion factor has the right dimension (2b), so you can't accidentally apply a mass conversion to a distance. Dimensional analysis catches category errors; unit conversion catches ratio errors. Together they would have caught both the Mars Climate Orbiter failure (Lockheed produced `PoundForce * USSecond`, NASA expected `Newton * Second` — the types are incompatible, assignment is a compile error) and the Gimli Glider incident (fuel calculated in `Kilogram` but loaded by `USPound` — again, incompatible types).

## 3: Annotations and Reflection - from Go, Rust, Java, etc.

  Needs more research. But records, types, variables, arrays, functions, etc could be tagged with annotation syntax. either back-tick (\`) like in Go annotations. or [[ ]] C++ attributes, or #[] in Rust attributes.

  The purpose of annotations would be to give libraries/units a way to do introspection and reflection.
  Perhaps reflect (the ability to modify itself, like in Lisp) is beyond the scope of Compact Pascal, although it might be an easier route towards macros than Rust's macros.

  Some example use cases would be to provide serializers for JSON to know which fields of a Record to import/export and under what name (primary use case in Go)

  A more exotic case would fit in the with next section on persistence.

## 4: Persistence via Host Imports - From PS-algol

  Persistence via host imports — this is the most architecturally interesting match. PS-algol's core insight is
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

## 5: Associative Tables as built-in abstractions - from PS-algol

  Associative tables as a built-in abstraction — PS-algol provides table, lookup(table, key), enter(table,value, key), scan(table, func) as standard functions backed by B-trees. In Compact Pascal, this could be a host-provided data structure via imports — the host maintains the B-tree, Pascal code just calls lookup/enter.  Useful as a standard library pattern even without persistence.

  Also of interest is Lua's associative tables and meta-tables. A subset of this might prove to be useful, if it can be mapped to a static language like Compact Pascal.
