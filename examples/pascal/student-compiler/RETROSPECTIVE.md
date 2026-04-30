# Set Type Implementation Retrospective

## Scope

Implement Pascal set types in a single-pass Pascal-to-WASM compiler with no AST.
Four failing tests: t052_set_basic, t053_set_compare, t054_set_char, t079_set_char_ops.
Approximately 2,200 lines of new/modified code in pascom.pas (from ~5,000 to 7,268 lines).

## Two Representations

The fundamental design decision was supporting two set representations:

- **Small sets** (`set of integer`, range 0..31): a single i32 bitmask on the WASM stack. 4 bytes. All operations are inline WASM instructions (i32.or, i32.and, i32.xor, etc.).
- **Large sets** (`set of char`, range 0..255): 32-byte memory bitmaps (8 x i32 words). Passed by address on the stack. Operations require helper functions that loop over the 8 words.

This dual representation was the source of most of the difficulty. Every code path that touches sets must ask: is this a 4-byte stack value or a 32-byte memory pointer? And when both operands aren't the same size, what then?

## What Went Wrong

### Bug 1: Constant large set constructors wrote data at the wrong offset

The set constructor for compile-time-constant large sets (e.g., `['A'..'Z', 'a'..'z']`) did this:

```pascal
fi := AllocData(32);           { allocate 32 bytes in data segment }
for setLo := 0 to 31 do
  SmallBufEmit(dataBuf, setBitmap[setLo]);  { append 32 more bytes }
```

`AllocData(32)` writes 32 zero bytes at position `fi` in the data buffer. Then `SmallBufEmit` appends the actual bitmap data *after* those zeros, at the wrong offset. The WASM address `fi` points to 32 bytes of zeros; the real data sits 32 bytes later where nothing references it.

This is a misunderstanding of how `AllocData` works. It reserves space by writing zeros in-place. The fix was to write directly into the already-allocated region:

```pascal
fi := AllocData(32);
for setLo := 0 to 31 do
  dataBuf.data[fi - DataBase + setLo] := setBitmap[setLo];
```

This bug was subtle because: (a) the compiler produced valid WASM, (b) wasm-validate passed, (c) the program ran without trapping — it just silently operated on all-zero sets. The symptom was that `'A' in letters` returned false for every character.

**Diagnosis method**: `wasm-objdump -s -j Data` on the generated WASM to inspect the data segment contents. This revealed the bitmap data was offset from where the code expected it.

### Bug 2: Empty set assigned to a large set variable

```pascal
var s1: set of char;
s1 := [];
```

The `[]` constructor always produces a small set: `i32.const 0` on the stack. But `s1` is a 32-byte `set of char`. The assignment code for large sets does `memory.copy(dst, src, 32)`, which needs a *source address* — not a bare i32 value.

Without a fix, the generated code would try to use the literal 0 as a memory address and copy 32 bytes from address 0, producing garbage or a trap.

The fix: after parsing the expression, check `lastExprSetSize`. If the expression produced a small set (4 bytes) but the target is a large set (32 bytes), drop the i32 from the stack and push `addrSetZero` — a statically-allocated 32-byte block of zeros in the data segment.

```pascal
if lastExprSetSize <= 4 then begin
  EmitOp(OpDrop);
  EnsureSetTemp;
  EmitI32Const(addrSetZero);
end;
```

The same size-mismatch problem appeared in binary operations (e.g., `largeSet + [3]`) and required the same pattern: detect the small operand, drop it, substitute a zero-filled address. For the left operand this was trickier because it was already below the right operand on the stack, requiring a local variable to temporarily hold the right side.

### Bug 3: Helper function index instability

The compiler uses an `Ensure*` pattern where helper functions (for fd_write, proc_exit, write_int, string operations, etc.) are lazily allocated when first needed. Each allocation shifts all subsequent function indices.

Set operations need five helper functions: union, intersect, difference, equality, subset. If these were allocated one-at-a-time as encountered during parsing, the index of already-emitted `call` instructions would be wrong — a call to "union" at index 7 would actually invoke "intersect" after a later helper gets inserted before it.

The solution followed the existing `EnsureStringHelpers` pattern: `EnsureSetHelpers` reserves all 5 function slots at once on first use. Only the slots actually needed get real bodies; unused slots get minimal stubs (just `end` for void helpers, `i32.const 0; end` for i32-returning ones).

## What Went Right

### The save/restore pattern for helper code generation

Building helper function bodies in a single-pass compiler is awkward because the main function's code is being emitted into `startCode` when you discover you need a helper. The pattern used throughout the compiler:

1. Save `startCode` to a local variable
2. Reinitialize `startCode`
3. Emit the helper body into the fresh `startCode`
4. Copy it to a separate buffer (`setHelperCode`)
5. Restore `startCode`

This worked cleanly for all five set helpers. The nested `SEmit`/`SEmitULEB128`/`SEmitSLEB128` procedures kept the helper-building code readable.

### Small set operations as inline WASM

For `set of integer` (0..31), every operation maps to one or two WASM instructions:

| Operation | WASM |
|---|---|
| Union (`+`) | `i32.or` |
| Intersection (`*`) | `i32.and` |
| Difference (`-`) | `i32.const -1; i32.xor; i32.and` |
| Equality (`=`) | `i32.eq` |
| Membership (`in`) | `i32.const 1; swap; i32.shl; i32.and; i32.const 0; i32.ne` |
| Subset (`<=`) | `a AND (NOT b) = 0` |

No helper function call, no memory access. This is about as efficient as set operations can be in WASM.

### Constant folding for set constructors

When all elements and ranges in a set constructor are compile-time constants (literals, const identifiers), the compiler folds them into a bitmap at compile time and either embeds it in the data segment (large set) or emits a single `i32.const` (small set). Only sets with variable elements go through the runtime bit-shifting path.

## Structural Complexity

The set implementation touched nearly every section of the compiler:

- **Type system**: new `tySet` kind, `size` field distinguishing 4-byte vs 32-byte sets
- **Variable declaration**: `set of integer` vs `set of char` type parsing, size determination
- **Constants**: compile-time bitmap folding, data segment allocation
- **Expression parsing**: set constructor `[...]` with elements and ranges, `in` operator, binary ops (+, -, *, =, <>, <=, >=)
- **Statement parsing**: set assignment with size-mismatch handling
- **Code generation**: five WASM helper functions with block/loop/br_if iteration
- **Section assembly**: type signatures, function entries, code bodies, stub generation
- **Module init**: new global variable initialization

The dual-representation design (stack i32 vs memory address) created a cross-cutting concern that touched every one of these areas. Any code that consumed a set expression had to check which representation it got and handle both cases.

## Takeaways

1. **`AllocData` writes zeros; don't append after it.** This was a misunderstanding of an existing API that cost significant debugging time. The fix was one line.

2. **Dual representations create combinatorial complexity.** Every binary operation has four cases: small/small, small/large, large/small, large/large. The small/small case is trivial (inline ops). The large/large case is clean (call helper). The mixed cases are where every bug hid.

3. **Lazy allocation of helper indices is fragile.** Reserving all slots upfront (the `EnsureSetHelpers` pattern) is more wasteful — unused helpers get stub bodies — but eliminates an entire class of index-stability bugs. The cost is a few bytes of dead code in the WASM output.

4. **`wasm-objdump` is essential.** When the compiler produces valid WASM that runs but gives wrong results, disassembly (`-d`) and data segment inspection (`-s -j Data`) are the only way to find out what actually got emitted. Printf-debugging doesn't work when your output format is binary.
