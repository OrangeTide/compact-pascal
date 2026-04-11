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

## 3: Annotations — Compile-Time Metadata for Declarations

  Annotations attach structured metadata to declarations. The compiler emits annotation tables into the WASM data segment and exports their addresses, making them accessible both to Pascal code at runtime and to the host via the export. This gives both sides the same view of annotated types — the host can do JSON marshalling, the guest can do its own serialization, and they share the same table.

  ### Why Not Full Reflection?

  The white paper excludes RTTI because automatic type descriptors for every type cause code size explosion and complicate single-pass emission. WASM's Harvard architecture (code and data in separate address spaces) makes runtime code introspection impossible — a program cannot inspect or modify its own code.

  Annotations are different: they are **opt-in**. Only annotated declarations get table entries. No annotations, no table, no cost. Lisp-style `reflect` is out of scope — Compact Pascal cannot modify its own code, and the single-pass compiler cannot replay declarations. But structured metadata about declarations that opted in is feasible and useful.

  ### Syntax: `[[ ]]`

  ```
  type
    UserRecord = record
      [[field:'user_id']]
      ID: integer;
      [[field:'display_name']]
      Name: string;
      [[field:'-']]             { skip this field in serialization }
      CacheKey: integer;
    end;
  ```

  The `[[` token is unambiguous in a single-pass parser. In standard Pascal, `[` opens set constructors and array indices, but `[[` — two consecutive open brackets — never occurs naturally. The lexer distinguishes `[[` from `[` with one character of lookahead, the same technique used for `<=` vs `<`. The closing `]]` is equally clean. C++ uses the same `[[ ]]` syntax for attributes, so the notation has precedent.

  An early bootstrap compiler can skip everything between `[[` and `]]` without understanding the contents, while still closely following the official grammar. This makes annotations forward-compatible — older compilers ignore annotations they don't recognize.

  Compiler directives (`{$...}`) remain separate. Directives control compiler behavior (range checks, memory layout, stack size). Annotations describe declarations (field names, export markers, persistence hints). The distinction is clear: directives are instructions to the compiler, annotations are metadata about the program.

  ### Annotation Kinds

  Annotations are restricted to specific, compiler-recognized kinds. Each kind has defined semantics — the compiler knows what to do with it. This is not a general-purpose extensibility mechanism like Java annotations or Rust derive macros.

  Planned kinds:

  | Kind | Applies to | Purpose |
  |------|-----------|---------|
  | `field` | Record fields | Serialization name mapping |
  | `export` | Procedures | Mark as WASM export |
  | `deprecated` | Any declaration | Compiler warning on use |
  | `persist` | Types, fields | Persistence participation (section 4) |
  | `index` | Record fields | Mark as indexed for associative tables (section 5) |

  The set of annotation kinds is compiler-defined and closed. User code cannot define new annotation kinds — this keeps the mechanism simple and the compiler single-pass.

  ### Annotation Tables in the Data Segment

  The compiler emits annotation metadata as initialized data in the WASM data segment — an annotation table. Each annotated type produces a sequence of entries. The table address is exported, so the host can read it directly from guest memory without a custom section.

  Table entries carry: offset, size, typeId, and name for each annotated field. Record types use record-start/record-end marker entries to encode nesting, giving tree structure in a flat table — the compiler emits markers as it enters and leaves record declarations, purely sequential, no tree held in memory.

  ```
  { Annotation table layout (conceptual) }
  { entry: tag (record-start|field|record-end), typeId, offset, size, nameLen, name[] }

  record-start  typeId=7  "UserRecord"
    field        typeId=1  offset=0   size=4  "user_id"        { integer }
    field        typeId=2  offset=4   size=256 "display_name"  { string }
  record-end    typeId=7  "UserRecord"
  ```

  The WASM module exports the table start address and entry count:

  ```wasm
  (global (export "__annotation_table") i32 (i32.const 1024))
  (global (export "__annotation_count") i32 (i32.const 3))
  ```

  This is the same pattern WASM uses for its own type and function sections — indexed entries with a count. The host reads the export, walks the table, and has full knowledge of annotated types, field layouts, and names. The host and guest share the same memory, so there is no serialization boundary — both sides read the same bytes.

  ### The `typeof` Operator

  The compiler assigns a numeric typeId to every type during compilation. `typeof(T)` evaluates to this typeId as a compile-time integer constant — no runtime introspection. The same typeId appears in annotation table entries, so Pascal code can match fields by type:

  ```
  var
    i: integer;
    entry: AnnotationEntry;
  begin
    for i := 0 to AnnotationCount - 1 do begin
      entry := AnnotationTable[i];
      case entry.typeId of
        typeof(integer): SerializeInt(basePtr, entry.offset, entry.size);
        typeof(string):  SerializeStr(basePtr, entry.offset, entry.size);
      end;
    end;
  end.
  ```

  Each `typeof(...)` arm is a compile-time constant, so this is a regular `case` statement — no dynamic dispatch, no type descriptors. The annotation table provides the runtime data (which fields exist, where they are), and `typeof` provides the compile-time bridge to handle each type correctly. This is not RTTI — it is opt-in metadata with compile-time type matching.

  ### Host-Side and Guest-Side Serialization

  Because the annotation table is in shared linear memory with an exported address, both sides can use it:

  - **Host-side:** The host (Rust, Zig, C) reads the exported `__annotation_table` address, walks the entries, and marshals record data to/from JSON, protobuf, database rows, etc. The host has full knowledge of field names, types, offsets, and sizes. No FFI calls needed — just memory reads.
  - **Guest-side:** Pascal code iterates the same table using the `AnnotationTable` global and `typeof` case dispatch. A Pascal unit could implement its own JSON writer, binary serializer, or debug printer using only the annotation table and standard I/O.
  - **Both at once:** The host provides JSON parsing via imports (fast, native), the guest provides the field-walking logic via the annotation table (type-aware, application-specific). Each side does what it is good at.

  This dual-access model falls naturally out of WASM's shared linear memory. No custom sections, no separate metadata formats — one table, two readers.

  ### What Annotations Are Not

  - **Not macros.** Annotations do not transform code. Rust's `#[derive(...)]` generates trait implementations by inspecting the AST — that requires multi-pass compilation. Compact Pascal's single-pass compiler cannot replay or transform declarations.
  - **Not automatic RTTI.** Unannotated types have no table entries and no runtime cost. The white paper's objection to RTTI — code size explosion from universal type descriptors — does not apply to opt-in metadata.
  - **Not self-modifying.** WASM's Harvard architecture prevents code introspection. Annotations describe data layout, not code structure. A program can read its annotation tables but cannot modify them or inspect its own instructions.

  **Open questions:**

  - Exact binary encoding of annotation table entries — fixed-size with padded names, or variable-length with length prefixes?
  - Should `typeof` be a reserved word or a built-in function? (Reserved word is simpler for the single-pass compiler.)
  - Naming convention for the exported globals (`__annotation_table`, `__annotation_count`, or something else)?
  - Should the compiler emit annotation tables for all annotated types automatically, or require an explicit directive to enable table generation?

## 4: Persistence via Host Imports — from PS-algol

  PS-algol's core insight is that persistence should be orthogonal to the language — you write normal code, and the runtime decides what persists based on reachability from a root. Programs written in PS-algol showed ~3x reduction in source code size compared to equivalent programs in Pascal with explicit database calls. Compact Pascal's WASM embedding model is a natural fit for this idea, but the implementation strategy is fundamentally different from PS-algol's.

  ### PS-algol's Approach (and Why It Doesn't Fit)

  PS-algol adds persistence to S-algol as standard functions — the compiler itself barely changes. All persistence work happens in the runtime:

  ```
  open.database(name, mode, user, password) → database handle
  get.root(database) → root pointer
  set.root(old_root, new_root)
  commit
  abandon
  close.database(root)
  ```

  Persistence is identified by reachability from the database root, like garbage collection identifies liveness. `set.root` makes a subgraph persistent; `commit` writes it to the store.

  The implementation machinery is substantial:

  - **PIDLAM** (Persistent ID to Local Address Map): a table that translates between in-memory object pointers (LONs) and persistent identifiers (PIDs). Every pointer dereference goes through this table. 14 bytes overhead per object.
  - **Threshing algorithm**: at commit time, breadth-first traversal from the root separates persistent objects from temporary ones. O(N²) worst case.
  - **Heap purge**: if GC cannot free enough space, the entire heap is serialized to the database and reloaded. This is the fallback for memory pressure.
  - **Two-stack model**: the interpreter maintains separate stacks for scalars and pointers so the GC can find roots.

  This is complex runtime machinery — exactly what Compact Pascal's "minimal runtime" goal avoids. The PIDLAM alone is a significant data structure, and the threshing algorithm requires heap traversal that depends on GC infrastructure. PS-algol's approach assumes a runtime that manages all memory allocation and can walk the heap at will.

  ### Compact Pascal's Approach: Host-Managed Persistence

  The key difference: in the WASM embedding model, the host has full visibility into guest memory. The host can read and write linear memory directly. Combined with the annotation tables from section 3, the host already knows the layout of every annotated record type — field offsets, sizes, type IDs, and serialization names. The host does not need a PIDLAM or threshing algorithm because it can serialize records directly by reading linear memory at the offsets described by the annotation table.

  Persistence becomes a set of host-provided imports:

  ```
  { Host imports for persistence }
  procedure OpenStore(name: string; mode: integer): integer; external;
  procedure CloseStore(handle: integer); external;
  procedure StoreRecord(handle: integer; typeId: integer; ptr: integer); external;
  function LoadRecord(handle: integer; key: string): integer; external;
  procedure CommitStore(handle: integer); external;
  procedure AbandonStore(handle: integer); external;
  ```

  When Pascal code calls `StoreRecord`, the host:
  1. Reads the annotation table (already exported, section 3) to find the record's field layout.
  2. Reads the record's bytes directly from linear memory at the given pointer.
  3. Serializes each field using the offset, size, typeId, and name from the annotation table.
  4. Writes the serialized form to the persistent store (SQLite, file, key-value store — host's choice).

  Loading is the reverse: the host reads from the store, writes field values into linear memory at the correct offsets, and returns the pointer. No PIDLAM, no threshing, no heap walking. The annotation table is the serialization schema.

  ### What This Looks Like in Practice

  ```
  program addressbook;

  type
    Address = record
      [[field:'house_number']]
      HouseNo: integer;
      [[field:'street']]
      Street: string;
      [[field:'town']]
      Town: string;
    end;

    Person = record
      [[field:'name']]
      Name: string;
      [[field:'phone']]
      Phone: string;
      [[field:'address']]
      Addr: Address;
    end;

  var
    store: integer;
    p: Person;

  begin
    store := OpenStore('addressbook.db', 1);

    p.Name := 'Ron Morrison';
    p.Phone := '555-0142';
    p.Addr.HouseNo := 42;
    p.Addr.Street := 'North Street';
    p.Addr.Town := 'St Andrews';

    StoreRecord(store, typeof(Person), addr(p));
    CommitStore(store);
    CloseStore(store);
  end.
  ```

  Compare with the PS-algol equivalent from the original paper — the structure is similar, but there is no `set.root`, no reachability-based persistence, no implicit commit-on-exit. Persistence is explicit: you call `StoreRecord` with a typed pointer, and the host does the rest. The 3x code reduction that PS-algol measured over explicit database calls in Pascal came from eliminating boilerplate serialization code — the annotation table achieves the same result through a different mechanism.

  ### Transaction Semantics

  PS-algol provides `commit` and `abandon` for transaction control. The WASM model can support the same semantics, but the implementation is simpler because the host controls the persistent store:

  - **Commit**: the host flushes buffered writes to the store. All `StoreRecord` calls since the last commit (or since `OpenStore`) become durable.
  - **Abandon**: the host discards buffered writes. The in-memory state is unchanged — only the store is rolled back.

  PS-algol's commit is complex because it must traverse the heap and decide what to persist (the threshing algorithm). Compact Pascal's commit is simple because persistence is explicit — the host already knows exactly which records were stored.

  ### Constraints and Dependencies

  - **Phase 5+ (New/Dispose)**: persistent data structures with pointer fields (linked lists, trees) require heap allocation. Stack-only records can be persisted in earlier phases, but the full value of persistence requires dynamic allocation.
  - **Annotation tables (section 3)**: the host's ability to serialize records depends on knowing the field layout. Without annotations, the host would need a separate schema definition, defeating the purpose.
  - **Nested records**: the record-start/record-end markers in the annotation table (section 3) handle nested record types like `Person` containing `Address`. The host walks the tree structure in the annotation table to serialize nested fields.

  ### What We Skip from PS-algol

  - **Reachability-based persistence.** PS-algol persists everything reachable from the root. This requires heap traversal and GC infrastructure. Compact Pascal uses explicit persistence — you choose what to store.
  - **PIDLAM.** No indirection table for persistent identifiers. Records are addressed by their linear memory pointer. The host translates between memory layout and persistent format using the annotation table.
  - **Threshing.** No algorithm to separate persistent from temporary objects. There is nothing to separate — persistence is explicit.
  - **Heap purge.** No fallback that serializes the entire heap under memory pressure. The host manages its own storage independently of guest memory.

  These simplifications are possible because the WASM embedding model gives the host capabilities that PS-algol's runtime had to build from scratch. The host already has what PS-algol's PIDLAM provides — the ability to read any object in guest memory by address — because linear memory is shared.

  ### The Trade-Off: Explicit vs. Automatic Persistence

  What we gain in simplicity we give up in orthogonality. PS-algol's strongest property is that persistence is transparent — the programmer writes normal code, and the runtime decides what persists based on reachability. You never call a "save" function. You set the root, commit, and everything reachable is durable. This is a genuinely different programming model, not just a convenience.

  Compact Pascal's explicit persistence is closer to what Java provides with JPA/Hibernate or what Rust provides with Diesel — you annotate your types, call store/load explicitly, and manage the object lifecycle yourself. This is well-understood territory, and the annotation table makes the boilerplate minimal, but it is not the paradigm shift that PS-algol represents. The programmer must decide what to persist and when, which means persistence is not orthogonal to the program's logic — it is part of it.

  A future extension could explore automatic persistence by combining annotations with GC reachability analysis (Phase 5+), moving closer to PS-algol's model. But that would require the heap walker and root-tracing machinery we are deliberately avoiding in this proposal.

  ### Schema Migration

  This proposal does not define a schema migration process. When a record type changes between program versions — fields added, removed, renamed, or retyped — existing data in the persistent store becomes incompatible with the new annotation table. This is a real problem that every persistence system must address.

  Precedents:

  - **Diesel (Rust)**: up/down migration scripts written in SQL. Each migration has a forward transformation and a rollback. The migration history is tracked in a table within the database itself.
  - **ActiveRecord (Ruby)**: similar up/down migrations, with a DSL for common operations (add column, rename column, change type).
  - **Protocol Buffers**: field numbering with explicit deprecation. Old fields are never reused. Readers skip unknown fields. Forward and backward compatibility are built into the wire format.
  - **PS-algol**: does not address this. Programs that change structure types are simply incompatible with old databases. (Category 5 on the persistence spectrum — data that exists between versions of a program — is stated as a goal but not solved by the implementation.)

  For Compact Pascal, the annotation table provides the raw material for migration: field names, types, offsets, and sizes for both the old and new schema are available to the host. A migration could be a host-side operation that reads the old schema from the stored annotation table, reads the new schema from the current program's annotation table, and transforms the data. But the mechanism for defining, ordering, and applying migrations is an open design question.

  ### Open Questions

  - How are pointer fields in records handled during serialization? A pointer to another record in linear memory is meaningless in the persistent store. Options: follow the pointer and serialize recursively (the annotation table has the nested structure), store a foreign key / record ID, or restrict persistent records to value-only fields.
  - Should `LoadRecord` return a fresh allocation (requires New/Dispose) or write into a caller-provided buffer?
  - Is there a query mechanism beyond key-based `LoadRecord`? This connects to section 5 (associative tables).
  - Should the store handle be a first-class value or a global implicit context (like PS-algol's current database)?
  - What is the schema migration strategy? Host-side transformation using old/new annotation tables, Pascal-side migration scripts, or something else?

## 5: Associative Tables as built-in abstractions - from PS-algol

  Associative tables as a built-in abstraction — PS-algol provides table, lookup(table, key), enter(table,value, key), scan(table, func) as standard functions backed by B-trees. In Compact Pascal, this could be a host-provided data structure via imports — the host maintains the B-tree, Pascal code just calls lookup/enter.  Useful as a standard library pattern even without persistence.

  Also of interest is Lua's associative tables and meta-tables. A subset of this might prove to be useful, if it can be mapped to a static language like Compact Pascal.
