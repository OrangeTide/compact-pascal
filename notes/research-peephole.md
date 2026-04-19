# Peephole Optimization for Compact Pascal

Research notes for an optional peephole optimizer in the cpas compiler.

## Design Goals

- **Plug-in architecture.** A student can skip this entirely and add it later.
  The optimizer is gated behind `{$IFDEF PEEPHOLE}` so the code is completely
  absent from the compiler WASM image when not defined.
- **Compile-time and runtime control.** When the peephole code *is* included:
  - `-O1` enables optimization (default when peephole is compiled in).
  - `-O0` disables it at runtime.
  - `{$OPT+/-}` directive toggles it per-region within source code.
  - When peephole is *not* compiled in, `-O1`/`-O0` and `{$OPT}` are silently
    ignored — no error, no effect.
- **Requires `-d` flag support in cpas.** The compiler needs a `-dSYMBOL`
  command-line option (like fpc) to define conditional compilation symbols.
  This is how `PEEPHOLE` gets defined when self-hosting:
  `wasmtime run compiler.wasm -- -dPEEPHOLE < cpas.pas > cpas-opt.wasm`

## Where It Fits in the Pipeline

The compiler emits WASM opcodes into code buffers (`startCode`, `funcBodies`,
`helperCode`) during parsing. The peephole optimizer operates as a **sliding
window on the code buffer during emission** — not a separate post-pass.

After each instruction is appended to the buffer, `TryPeephole` checks whether
the trailing bytes match a known pattern and rewrites in place by rewinding the
buffer write pointer.

- No second pass over the binary
- No extra memory beyond the existing code buffer
- The rest of the compiler is untouched

## Window Size

A fixed lookback window. The minimum useful window is 2 instructions (covers
`local.set/get → tee` and identity elimination), but **longer windows are
worth investigating** for several reasons:

- **Constant folding** across 3 instructions: `i32.const A / i32.const B /
  i32.add` → `i32.const (A+B)`. This is a 3-instruction pattern.
- **Pathological sequences from single-pass codegen.** A single-pass compiler
  with no AST or IR can produce unnecessarily long instruction sequences that
  a multi-instruction window could collapse. Examples:
  - Repeated stack spill/reload around subexpressions:
    `local.set tmp / ... / local.get tmp / local.set tmp / local.get tmp`
  - Redundant address computation: computing `base + offset` when the same
    address was just computed and is still inferrable from context.
  - Nested expression evaluation that stores intermediate results to locals
    and immediately reloads them.
- **Instruction reordering.** Some pathological codegen sequences could benefit
  from reordering independent instructions to enable further pattern matches.
  For example, if the compiler emits `i32.const 0 / local.get X / i32.add`,
  a commutativity-aware optimizer could recognize this as `local.get X`
  (adding zero). However, reordering adds complexity and risks changing
  semantics if the window spans effectful operations. This is an area to
  revisit once the compiler is working and real pathological patterns are
  observable in practice.

The window size should be a compile-time constant (e.g., `const PeepWindow =
12;`) so students can experiment with different sizes. The pattern matcher
only looks back as far as the longest pattern it knows about.

## Matching Strategy: Switch/Case

A switch/case on the trailing opcode bytes. This is transparent, needs no
external tooling (no gperf), and students can read and understand every
pattern. The pattern set for a WASM stack machine is small enough (10-20
patterns) that a hash table is not justified.

```pascal
op1 := buf[bufPos - prevLen];  { previous instruction's opcode }
op2 := buf[bufPos - 1];        { just-emitted opcode }
case (op1 shl 8) or op2 of
  ($21 shl 8) or $20: { local.set X / local.get X → local.tee X }
    ...
end;
```

For patterns involving operands (constant folding), the matcher decodes
trailing LEB128 values from the buffer to extract and combine constants.

## Target Patterns

### Redundant local access (highest frequency)

| Pattern | Replacement | Bytes saved |
|---|---|---|
| `local.set X` / `local.get X` (same X) | `local.tee X` | 2-3 |
| `global.set X` / `global.get X` (same X) | defer `global.set`, keep on stack | 2-3 |

### Constant folding (3-instruction window)

| Pattern | Replacement | Bytes saved |
|---|---|---|
| `i32.const A` / `i32.const B` / `i32.add` | `i32.const (A+B)` | ~4 |
| `i32.const A` / `i32.const B` / `i32.mul` | `i32.const (A*B)` | ~4 |
| `i32.const A` / `i32.const B` / `i32.sub` | `i32.const (A-B)` | ~4 |

### Identity/absorbing operations

| Pattern | Replacement | Bytes saved |
|---|---|---|
| `i32.const 0` / `i32.add` | (remove both) | ~3 |
| `i32.const 0` / `i32.sub` | (remove both) | ~3 |
| `i32.const 1` / `i32.mul` | (remove both) | ~3 |
| `i32.const 0` / `i32.or` | (remove both) | ~3 |

### Double negation

| Pattern | Replacement | Bytes saved |
|---|---|---|
| `i32.eqz` / `i32.eqz` | (remove both) | 2 |

### Strength reduction (historical interest)

| Pattern | Replacement | Bytes saved |
|---|---|---|
| `i32.const 2` / `i32.mul` | `i32.const 1` / `i32.shl` | 0 |
| `i32.const 4` / `i32.mul` | `i32.const 2` / `i32.shl` | 0 |
| `i32.const (2^N)` / `i32.mul` | `i32.const N` / `i32.shl` | 0 |

These save zero bytes and are unlikely to be faster on modern WASM runtimes —
the JIT in V8, SpiderMonkey, wasmtime, etc. almost certainly recognizes
power-of-two multiplies and lowers them to shifts internally. But this was
a classic optimization on real hardware from the 1970s through 1990s — the era
of Pascal's heyday — and it is included as a historical teaching point. A
student implementing this pattern gets to think about the relationship between
source-level optimization, compiler optimization, and runtime optimization,
and why the same transform can matter on one layer and be redundant on another.

## Implementation Size

Estimated 100-150 lines of Pascal:
- `TryPeephole` procedure called after each opcode emission (~20 lines)
- Pattern matching switch/case (~80-100 lines for ~12 patterns)
- Helper to decode trailing LEB128 values for constant folding (~20 lines)
- Runtime flag check (`if optLevel > 0 then TryPeephole`)

All wrapped in `{$IFDEF PEEPHOLE}`.

## Prerequisites

- **`-d` flag support in cpas.** The compiler must parse `-dSYMBOL` from
  command-line arguments (via WASI `args_get`) and register the symbol for
  `{$IFDEF}`/`{$IFNDEF}` conditional compilation. This is independently
  useful — not just for peephole.
- **`-O` flag support.** Parse `-O0` and `-O1` from the command line. Default
  to `-O1` when peephole is compiled in. Store as a global `optLevel` variable.

## Tutorial Placement

**Addendum C** (not Appendix C) in the tutorial book. The label matters.
Appendices A and B are short reference tables — WASM opcodes, grammar. This
piece is a 500–800-line walkthrough with working code. Calling it an appendix
misleads the reader about the length and the depth. "Addendum" is honest:
added on, optional, distinct from the reference material.

**Order in the tutorial:**

1. Chapters 1–10
2. Afterword (sketches several directions for extending the compiler — add a
   one-paragraph pointer to Addendum C as one of those directions)
3. **Addendum C: Retrofitting a Peephole Optimizer** (new, ~500–800 lines)
4. Appendix A (WASM instruction reference)
5. Appendix B (grammar)

The addendum sits after the Afterword because it is substantive content, not
reference material. The appendices follow because they are lookup tables the
reader will consult repeatedly.

**What the addendum covers:**

- Why stack-machine compilers produce characteristic redundancies
- The sliding-window technique on byte buffers
- **The retrofit story.** This is the stretch goal. We did not plan for an
  optimizer when we first designed the emit layer. The addendum teaches the
  reader what it takes to insert one into existing code: auditing call sites,
  finding the right hook point, preserving behavior under `-O0`, verifying
  the existing test suite still passes byte-for-byte.
- Pattern matching on raw WASM bytecode
- Compile-time conditional compilation (`{$IFDEF}`) as a real-world technique
- The trade-off between compiler image size and output quality
- Historical context: strength reduction and the shift-vs-multiply story

## Hook-Point Audit

**This is the retrofit challenge.** `CodeBufEmit` — the byte-level append — is
not the right hook. It is called from ~20 sites in cpas.pas, many of which
emit raw bytes that are not opcode boundaries (LEB128 continuation bytes,
block-type bytes, section framing, alignment/offset immediates). Hooking
there would see the compiler's instruction stream as an unframed byte soup.

Survey of `CodeBufEmit` callers in cpas.pas (as of M11, 9,599 lines):

| Call site | Buffer | What it emits | Peephole applies? |
|---|---|---|---|
| `EmitULEB128` / `EmitSLEB128` | any | operand bytes for prior opcode | No — sub-emit |
| `EmitOp` | `startCode` | single-byte opcodes with no operand | Yes |
| `EmitI32Const` | `startCode` | `0x41` + SLEB128 value | Yes, after value |
| `EmitCall` | `startCode` | `0x10` + ULEB128 funcidx | Yes, after idx |
| `EmitI32Store` / `Store8` | `startCode` | opcode + align + offset | Yes, after offset |
| `EmitI32Load` / `Load8u` | `startCode` | opcode + align + offset | Yes, after offset |
| `EmitMemoryCopy` | `startCode` | fixed 4-byte prefix sequence | Yes, after last byte |
| `EmitHelper*` family | `helperCode` | same shapes, different buffer | Yes, same rules |
| Inline `CodeBufEmit(startCode, ...)` at line 4232 | `startCode` | mid-instruction bytes inside EmitSkipLine | No — sub-emit |
| Section builder at line 6315 | `funcBodies` | byte-copy from startCode to funcBodies | No — bulk copy |
| `WriteOutputByte` (line 6525) | `outBuf` | final binary serialization | **Never** — already optimized |
| `secCode` block at 8382+ | `secCode` | hand-written built-in helpers (`overflow_add`, `str_copy`, etc.) | No — fixed, audited code |

**The right hook is "instruction boundary," not "byte append."** Call
`TryPeephole(b)` from every Emit* helper, *after* the complete instruction
(opcode + all immediates) has been appended. The LEB128 sub-helpers and raw
`CodeBufEmit` calls inside larger instruction sequences do not call it.

This means a retrofit touches roughly 10 Emit* call sites. It is invasive but
localized — all in a contiguous band of cpas.pas around lines 1996–2068 and
6786–6809. No changes to the parser, the symbol table, or the section
writer.

**Rejected alternative: hook `CodeBufEmit` and track state.** Teaching a
byte-level function "what instruction am I in the middle of" requires
replicating the WASM instruction-length grammar inside the optimizer. That
is more complex than the optimizer itself. Reject.

**Rejected alternative: post-pass over the finished buffer.** A post-pass
would need to re-parse the WASM instruction grammar to find opcode
boundaries. Same problem as the byte-level hook, plus a second pass over the
code. Reject.

## Buffer Scoping

The optimizer takes the buffer as a parameter: `TryPeephole(var b: TCodeBuf)`.
Three buffers are active during compilation:

- `startCode` — current function body being emitted. Push/popped on the
  `savedCodeStack` when entering a nested procedure. Peephole applies.
- `helperCode` — long-lived buffer for emitted helper functions (not the
  hand-written `secCode` built-ins). Peephole applies, through the
  `EmitHelper*` family.
- `secCode` — hand-authored built-in helpers (`overflow_add`, `str_copy`,
  etc.) emitted via direct `CodeBufEmit` calls at lines 8382+. These are
  carefully written fixed sequences. Peephole does **not** apply — the
  author already hand-optimized them, and more importantly, they are not
  emitted through the Emit* helpers that call `TryPeephole`.

Pattern matches must not look back past the start of the current function
body. When `startCode` is reset at the top of a new function (via
`CodeBufInit`), the first few instructions have nothing behind them. The
pattern matcher's bounds check (`if b.len < prevLen then exit`) handles this
naturally.

## Retrofit Framing

The tutorial's honest story is: the emit layer was not designed with an
optimizer in mind. Chapter 3 introduced `EmitOp`, `EmitI32Const`, etc. as
thin wrappers around `CodeBufEmit`. They were the simplest thing that could
work. Adding peephole optimization later requires auditing every call site,
identifying the instruction boundaries, and inserting a hook.

This is how optimization gets added to most compilers in practice. Very few
compilers start with a designed-for-optimization IR on day one — most start
with direct emission, ship, and retrofit later when someone measures output
size or runtime. The retrofit pattern is a transferable skill.

The Addendum C lesson is not "here is a peephole optimizer, copy it in." It
is: "here is how you would locate the right place to insert one in code
that was not built for it."

## Open Questions

- **What pathological patterns does cpas actually produce?** This should be
  revisited once the compiler is emitting real code. Run the compiler on
  non-trivial programs, disassemble with `wasm-objdump -d`, and look for
  repeated idioms. The pattern table should be driven by observed data, not
  speculation.
- **Instruction reordering.** Worth investigating once real codegen patterns
  are observable. The risk is complexity and subtle correctness bugs — needs
  careful thought about which instructions commute safely.
- **Interaction with WASM validation.** Peephole rewrites must preserve
  WASM type safety (stack typing). The patterns listed above all preserve
  stack types, but any new patterns need verification.
- **Cascading rewrites.** After one peephole fires, the shortened sequence
  might enable another match. Should `TryPeephole` loop until no more matches
  are found, or run once per emission? Looping is more thorough but adds
  complexity. Start with single-fire and revisit if cascading patterns are
  observed in practice.
