# SNOBOL4

**Designer:** Ralph Griswold, Ivan Polonsky, David Farber
**Developer:** Bell Labs
**Released:** 1966
**Paradigm:** String processing, pattern matching, imperative
**Influenced:** Icon, SL5, AWK
**Wikipedia:** https://en.wikipedia.org/wiki/SNOBOL

## Core Concept

Every SNOBOL4 statement evaluates to either **success** or **failure**. This is the
fundamental control signal of the language — not boolean values, not exceptions, but
a binary outcome that drives all control flow. Success produces a value (which may be
null). Failure produces no value — only a signal. Success and failure are control
signals only; they cannot be stored in a variable.

## Goto as the Only Conditional

SNOBOL4 has no `if`/`else`, no `while`, no `for`. The **goto field** at the end of a
statement is the only conditional control structure:

| Form | Meaning |
|------|---------|
| `:(label)` | Unconditional transfer |
| `:S(label)` | Transfer only on success |
| `:F(label)` | Transfer only on failure |
| `:S(l1) F(l2)` | Transfer to l1 on success, l2 on failure |

If a conditional goto's condition does not apply (e.g., `:S(X)` but the statement
failed), execution falls through to the next sequential statement.

Example — copy input to output, counting lines:

```snobol
N = 0
COPY    OUTPUT = INPUT           :F(DONE)
        N = N + 1                :(COPY)
DONE    OUTPUT = 'THERE WERE ' N ' LINES'
```

When `INPUT` hits EOF, it **fails**, the assignment is not performed, and control
transfers to `DONE`. No sentinel values, no boolean tests.

## Failure Propagation Through Expressions

When an expression within a statement fails, the **entire statement fails immediately**
with no further evaluation:

- If `INPUT` fails (EOF), the assignment `OUTPUT = INPUT` does not execute.
- If a function call in the RHS fails (via `FRETURN`), the assignment is skipped.
- Comparison operators like `LT(X, Y)` succeed (returning null) or fail — they do
  not return boolean values.

The negation (`~`) and interrogation (`?`) unary operators manipulate success:

- `~expr` — succeeds (returning null) if `expr` fails; fails if `expr` succeeds.
- `?expr` — succeeds (returning null) if `expr` succeeds; fails if `expr` fails.
  Used to discard a value while keeping the success signal.

## Function Success/Failure

User-defined functions use three special transfer labels:

| Label | Effect |
|-------|--------|
| `RETURN` | Return successfully with a value |
| `FRETURN` | Return **failure** — no value; calling statement fails |
| `NRETURN` | Return a variable **name** (lvalue) rather than a value |

Example:

```snobol
        DEFINE('SHIFT(S,N)')               :(SHIFT_END)
SHIFT   S LEN(N) . FRONT REM . REST       :F(FRETURN)
        SHIFT = REST FRONT                 :(RETURN)
SHIFT_END
```

If the pattern match fails (string too short), control transfers to `FRETURN`, and
the calling statement sees failure.

Built-in functions follow the same protocol: `CONVERT(X,T)` fails if conversion is
impossible, `INTEGER(X)` fails if X is not an integer.

## Pattern-Matching Backtracking

SNOBOL4's pattern matcher searches for matches by trying alternatives and backtracking
on failure. Four built-in patterns control this:

| Pattern | Behavior |
|---------|----------|
| `FAIL` | Always fails; triggers backtracking to sibling alternatives |
| `SUCCEED` | Always succeeds (matches null); infinite alternatives |
| `FENCE` | Matches null on first try; ABORTs if backtracked into (commitment point) |
| `ABORT` | Immediately terminates entire match with failure |

Classic use — enumerate all substrings:

```snobol
S ARB . OUTPUT FAIL
```

`ARB` matches successively longer substrings. The conditional assignment `.` captures
each to `OUTPUT`. Then `FAIL` forces backtracking to the next `ARB` alternative.
This continues until all alternatives are exhausted.

## Features of Interest

- **Failure as control flow.** Success/failure replaces booleans entirely. Comparisons
  succeed or fail rather than returning true/false. This is the conceptual origin of
  Icon's goal-directed evaluation.

- **FRETURN for function failure.** Functions can signal "I have no result" as a normal
  control flow path, distinct from returning a value. The caller decides what to do
  with failure via `:F()`.

- **Negation operator.** The `~` operator inverts success/failure, providing a clean
  way to test for the absence of something.

- **Pattern-level backtracking control.** `FAIL`, `FENCE`, and `ABORT` give explicit
  control over how deeply backtracking searches. This influenced Prolog's cut and
  Icon's generators.

## References

- Griswold, R.E., Poage, J.F., Polonsky, I.P., *The SNOBOL4 Programming Language*,
  2nd ed., Prentice-Hall, 1971.
- Burks, SNOBOL4 Tutorial: https://www.regressive.org/snobol4/docs/burks/tutorial/
- SNOBOL4 Reference (berstis.com): http://berstis.com/s4ref/
- Wikipedia: https://en.wikipedia.org/wiki/SNOBOL
