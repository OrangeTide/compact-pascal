# Icon

**Designer:** Ralph Griswold
**Developer:** University of Arizona
**Released:** 1977
**Paradigm:** Goal-directed evaluation, generators, string processing
**Influenced by:** SNOBOL4, SL5, Algol
**Influenced:** Python (generators/yield), Unicon, Converge
**Website:** https://www2.cs.arizona.edu/icon/
**Wikipedia:** https://en.wikipedia.org/wiki/Icon_(programming_language)

## Core Concept

Icon replaces boolean values entirely with **success** and **failure** as expression
outcomes. Every expression either **succeeds** (producing a result value) or **fails**
(producing no value). Combined with **generators** — expressions that can produce
multiple values on demand — this creates **goal-directed evaluation**: the language
automatically searches for combinations of values that make an overall expression
succeed.

## Success and Failure

There is no boolean data type. Comparison operators succeed or fail:

```icon
if x < 5 then write("small")    # < either succeeds or fails
```

When `<` succeeds, it returns its right operand (here, 5). When it fails, it produces
nothing and the `then` branch is skipped. This is not exception handling — failure
is the normal, expected "no more values" signal.

## Generators

A **generator** is an expression that can produce multiple values. When first evaluated
it produces its first result. If the enclosing context needs another value (because the
first did not satisfy some condition), the generator is **resumed** to produce its next
result. When it has no more results, it **fails**.

Built-in generators:

```icon
find("or", "the work of an ordinary person")  # generates positions 8, 19, 26
1 to 10          # generates integers 1 through 10
!x               # generates elements of list/string x
key(T)           # generates keys of table T
```

User procedures become generators via `suspend`:

```icon
procedure findodd(s1, s2)
   every i := find(s1, s2) do
      if i % 2 = 1 then suspend i
end
```

`suspend` yields a value to the caller but preserves execution state so the procedure
can be resumed. This directly inspired Python's `yield`.

## Goal-Directed Evaluation

When a sub-expression is a generator, Icon automatically resumes it if the current
result does not lead to overall success:

```icon
write(5 < find("or", sentence))
```

1. `find` generates its first position (say, 3).
2. `5 < 3` fails.
3. The system **backtracks** to `find`, which generates its next position (say, 23).
4. `5 < 23` succeeds, returning 23.
5. `write(23)` executes.

No explicit loop or retry logic is needed.

## The `every` Construct

`every` exhausts a generator, driving it to produce all results:

```icon
every write(find("or", sentence))     # writes ALL positions
every i := 1 to 10 do write(sqrt(i))  # iterates 1..10
every write(!list)                     # writes all list elements
```

Key distinction from `while`: `every` **resumes generators** in its control expression,
while `while` **re-evaluates** its control expression from scratch each iteration.

## The `fail` Statement

Procedures signal failure in three ways:

| Mechanism | Effect |
|-----------|--------|
| `fail` | Procedure fails, producing no value |
| `return expr` | Succeeds with a single value (cannot be resumed) |
| `suspend expr` | Succeeds, yields value, can be resumed |
| Fall off end | **Fails by default** — a notorious source of bugs |

## Bounded vs. Unbounded Expressions

A **bounded** expression is one where backtracking cannot propagate outward. Most
control structure contexts (`if` condition, `while` condition, loop body) are bounded.
Backtracking only occurs **within** a single expression — it does not cross statement
boundaries. This prevents the need for unlimited state-saving memory.

| Context | Bounded? | Behavior |
|---------|----------|----------|
| `if` condition | Yes | Only first result matters |
| `while` condition | Yes | Re-evaluated, not resumed |
| `every` expression | No | Generator is exhausted |
| Conjunction `e1 & e2` | No | `e1` resumed if `e2` fails |

## Comparison to Exception Handling

| Aspect | Icon Success/Failure | Exceptions |
|--------|---------------------|------------|
| Semantics | "No (more) values" — normal | "Something went wrong" — abnormal |
| Frequency | Pervasive; happens constantly | Rare; indicates errors |
| Value produced | Failure produces nothing | Exception carries error info |
| Control flow | Drives generators, loops | Unwinds stack to handler |
| Backtracking | Failure can resume generators | No automatic retry |

Icon has a **separate** error-handling mechanism for genuine exceptional situations.
Failure and errors are orthogonal concepts.

## Known Limitations

From Tratt's analysis (implementing Icon-style evaluation in Converge):

1. **Default failure is dangerous.** Procedures that fall off the end silently fail.
   Most non-generator procedures should succeed, but Icon's default punishes the
   common case. This caused significant debugging difficulty.

2. **Backtracking is too weak for general use.** Icon only reverses variable assignments
   during backtracking — not mutations to lists, tables, or other structures.

3. **Backtracking is inherently local.** Constrained to bounded expressions, it cannot
   cross statement boundaries. Less powerful than Prolog-style backtracking.

4. **Performance cost.** Failure frame operations consume approximately 10% of total VM
   execution time and represent 25–30% of bytecode operations.

5. **No boolean type.** The absence of booleans makes it awkward to store and pass
   truth values. You have to use conventions like `1`/`&null` or the `\x` test.

## Features of Interest

- **Goal-directed evaluation.** Automatic backtracking within expressions eliminates
  explicit search loops for many common patterns. The system tries alternatives until
  one works.

- **Generators as first-class concept.** `suspend` creates coroutine-like generators
  that integrate seamlessly with the success/failure model. This was novel in 1977
  and directly influenced Python's generators (2001).

- **Failure as normal control flow.** The `fail` statement provides a clean way for
  functions to say "I have no result" without exceptions, error codes, or sentinel
  values. Loop constructs naturally terminate on failure.

- **Bounded expressions prevent runaway backtracking.** The bounded/unbounded
  distinction is a practical engineering decision that limits backtracking scope,
  avoiding Prolog's unbounded search problem.

- **Orthogonality of failure and errors.** Treating "no value" and "something went
  wrong" as separate concepts avoids the confusion of using exceptions for control
  flow or error codes for normal flow.

## References

- Griswold, R.E. and Griswold, M.T., *The Icon Programming Language*, 3rd ed.,
  Peer-to-Peer, 1996.
- Griswold, R.E., "Expression Evaluation in Icon," TR 80-21, University of Arizona,
  1980. https://www2.cs.arizona.edu/icon/ftp/doc/tr80_21.pdf
- Icon Overview (IPD266): https://www2.cs.arizona.edu/icon/docs/ipd266.htm
- Tratt, L., "Experiences with an Icon-like Expression Evaluation System,"
  *ACM TOPLAS*, 2010.
  https://tratt.net/laurie/research/pubs/html/tratt__experiences_with_an_icon_like_expression_evaluation_system/
- Tratt, L., "Some Lessons Learned from Icon," 2007.
  https://tratt.net/laurie/blog/2007/some_lessons_learned_from_icon.html
- Wikipedia: https://en.wikipedia.org/wiki/Icon_(programming_language)
