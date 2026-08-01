# Spec review: standalone methods, interfaces, and the module story

Status: external review, July 2026. A read of the Extensions chapter and the
formal grammar in `doc/compact-pascal-ref.md`, done from the skjegg project
while evaluating these features for Excelsior. None of the reviewed features
are implemented in `cpas` yet (per `doc/cpas-status.md`, and interfaces also
depend on procedural types, which are unimplemented), so every issue below is
fixable in the spec before any code exists. That is the cheap time to fix
them.

Made by a machine. PUBLIC DOMAIN (CC0-1.0)


## Summary

The designs are sound and the grammar is clean: `ProcDecl` left-factors on
`for` and stays LL(1), and the implement block is self-contained and
single-pass verifiable. The problems found are spec gaps (rules the reference
does not state) rather than design flaws, plus one real seam between the two
method systems. They are listed in decreasing order of importance.


## Gap 1: receiver addressability (correctness gap)

The reference says: "When calling a pointer-receiver method on a value, the
compiler automatically takes the address."

The hole is temporaries. Structured returns create them, so this compiles
under the current wording:

    Origin.Rename('X');    { takes the address of a temporary }

The mutation lands in the temporary and is silently discarded. Go forbids
exactly this case: a pointer-receiver method call requires an addressable
operand (a variable, field, or dereference; not a function result or other
rvalue). The spec needs that sentence. Suggested rule: auto-address applies
only to addressable designators; calling a pointer-receiver method on a
temporary is a compile error.

## Gap 2: field/method name collision (resolution rule missing)

`MyCat.Name` where `TCat` has a field `Name` and a method `Name` exists: the
reference never says which wins. Its own `IPet` example has both a `Name`
field and a `Name` function, and only works inside the implement block
because Pascal's function-result assignment shadows there.

Pick one rule and state it. Recommended: a method may not share a name with
a field of its receiver type (compile error at the method declaration).
Fields-shadow-methods also works but produces spooky far-away breakage when
a field is later added to a record.

## Gap 3: the two-method-system seam (design decision needed)

Standalone `for` methods are dot-callable. Implement-block methods satisfy
interfaces. The reference does not say whether these overlap:

- Can an implement block satisfy a signature with an existing standalone
  method instead of redefining the body?
- Are implement-block methods dot-callable on the concrete type?

As written, a type that wants both `MyCat.Greet('Alice')` and `IPet`
conformance defines `Greet` twice, or writes a wrapper. Recommended
resolution: make the implement block a conformance declaration rather than a
second definition site. When the block closes, any interface signature not
defined inside the block is matched against standalone methods of the
receiver type; only the missing ones must be written in the block. That
preserves single-pass verification (all candidates are already declared,
by declare-before-use) and removes the duplication.

The reverse question (dot-callability of block methods) can then be answered
"no" cleanly: the block declares conformance, the standalone form declares
the type's own surface.

## Gap 4: interface value lifetime (Self can dangle)

An interface value stores a Self pointer to the concrete data. Store one in
a global, or return one, and Self outlives the record's stack frame. Pascal
tradition may well answer "that is the programmer's problem", but the
reference should say so explicitly, in one sentence, next to the
representation section. Otherwise the first user to hit it will file it as a
compiler bug.

## Smaller items

- **Function-method header readability.** `function Area for r: TRect:
  integer;` puts two colons with different meanings in sequence; with
  parameters it becomes `function F for r: T (a: integer): integer;`. It
  parses fine (LL(1)); humans will misread it. Consider parentheses around
  the receiver, `function Area for (r: TRect): integer;`, which is also
  where Go landed.
- **Method scoping and overloading.** The grammar permits method
  declarations anywhere a ProcDecl is allowed, including nested scopes.
  State the intent (module scope only is simplest). Also state that the same
  method name may be declared for different receiver types, and whether a
  plain procedure of the same name may coexist.
- **"Structural typing" is the wrong label.** The reference calls interfaces
  structural, but conformance is explicit via the implement block. What CP
  actually has is structural signatures with explicit, single-pass-verified
  conformance. That is closer to Rust's `impl Trait for Type` than to Go.
  This is a better design than Go's implicit satisfaction for a
  declare-before-use language, so describe it accurately.
- **Module boundary type safety.** The `{$EXPORT}`/`{$IMPORT}` story is
  honest and cheap, but importers re-declare signatures by hand, so drift
  between exporter and importer surfaces at link time or later. When this
  starts to hurt, the fix is a compiler-generated interface file consumed by
  importers, not a hand-written `unit` header. (Excelsior independently
  reached the same conclusion with its generated `.exi` files; two projects
  converging on generated-interface is decent evidence for it.)


## Selling the interesting parts

Advice on positioning, for the white paper and any announcement text.

1. **Lead with the implement block, not with "Go-like".** Implicit interface
   satisfaction is Go's most criticized feature (accidental conformance,
   satisfaction discoverable only by tooling). CP keeps Go's retroactive,
   inheritance-free polymorphism but makes conformance explicit and verifies
   it at a single point, in one pass, with declare-before-use semantics that
   are native to Pascal. That is a real differentiator: "Go's interfaces
   with the accidents removed, verified the Pascal way." Do not undersell it
   as merely structural typing.
2. **Sell single-pass as the through-line.** Standalone methods, implement
   blocks, and forward declarations with full repeated headers are all the
   same story: every feature is checkable the moment its closing token is
   read. That is the language's identity, and it is rare among modern
   designs. Frame every extension in those terms and reject extensions that
   cannot be framed that way (the white paper already does this for traits
   and generics; keep that discipline).
3. **The method receiver is the anti-OOP pitch.** "Any type can have
   methods, no classes, no inheritance, no vtable unless you ask for an
   interface" resonates with exactly the audience that still writes Pascal.
   The pitch writes itself as a before/after against Object Pascal class
   boilerplate.
4. **The fat-value representation is a feature, not an apology.** Inline
   Self-plus-slots means interface dispatch is one indirect call with no
   hidden global tables, which suits WASM's indirect-call model and makes
   costs visible. Present itables as a future optimization, as the reference
   already does, not as a missing piece.
5. **Pair the module story with its escape hatch.** "The WASM module is the
   unit" is a clean pitch for the embedding audience, but immediately name
   the known cost (hand-declared imports can drift) and the planned answer
   (generated interface descriptions), so the omission of `unit`/`uses`
   reads as a decision rather than a gap.
