# Zonnon

**Designers:** Jürg Gutknecht et al. (ETH Zürich)
**Released:** ~2005
**Target:** .NET CLR
**Paradigm:** Object-oriented, concurrent, imperative, structured
**Website:** https://zonnon.org/
**Repository:** https://github.com/zonnonproject/compiler
**Wikipedia:** https://en.wikipedia.org/wiki/Zonnon

## Core Concept

Zonnon is a general-purpose language in the Pascal → Modula → Oberon lineage, focused
on **active objects** and **compositional inheritance**. It introduces the concept of
active objects to represent real-world concurrent entities, with interactions defined by
**syntax-controlled dialogs**. The active object concept was imported from Active Oberon
and generalized into a unified model of hierarchic activities.

## Program Units

Zonnon has four kinds of program units:

| Unit | Instantiated? | Purpose |
|------|--------------|---------|
| `object` | Runtime | Encapsulates state and behavior; can be active |
| `module` | Runtime | Singleton, like a static class |
| `definition` | Compile-time | Abstract interface specification |
| `implementation` | Compile-time | Composition unit for implementing definitions |

## Active Objects and Activities

Objects can contain **activities** — encapsulated threads that come in two flavors:

- **Local activities:** Internal concurrent threads within an object.
- **Agent activities:** Threads that interact with external objects via protocols.

This model makes concurrency a property of objects rather than a separate language
mechanism.

## Compositional Inheritance

Zonnon uses **aggregation-based inheritance** rather than classical subclassing. An
object or module is composed of several functional components, each presenting itself
through a `definition`. This is closer to Go-style interface composition than Java-style
class inheritance.

## Additional Features

- **Operator overloading** for custom types
- **Exception handling** (try/except)
- **Syntax-controlled dialogs** — interaction protocols between active objects defined
  by grammar-like syntax specifications

## .NET Target

Zonnon compiles to .NET CLR bytecode, making it interoperable with C#, F#, and other
.NET languages. A Visual Studio integration was developed.

## Significance

Zonnon represents the ETH Zürich school's most recent attempt to evolve the
Pascal/Oberon lineage with modern concurrency. The compositional inheritance model
and syntax-controlled dialogs are novel contributions. The active object model is
relevant to any language considering built-in concurrency.

## References

- J. Gutknecht et al., "Project Zonnon: A Compositional Language for Distributed
  Computing," IEEE, 2008. https://ieeexplore.ieee.org/document/4464019
- "Zonnon for .NET — A Language and Compiler Experiment," Springer LNCS, 2003.
  https://link.springer.com/chapter/10.1007/978-3-540-45213-3_18
- Zonnon website: https://zonnon.org/
- GitHub: https://github.com/zonnonproject/compiler
