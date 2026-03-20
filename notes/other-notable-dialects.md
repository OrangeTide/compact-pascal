# Other Notable Pascal Dialects

A survey of Pascal-family languages with features of potential interest, beyond the
major dialects documented separately in this directory.

## Component Pascal

**Origin:** ETH Zürich spin-off (Oberon microsystems), ~1997
**Lineage:** Pascal → Modula-2 → Oberon → Oberon-2 → Component Pascal

A refinement of Oberon-2 with a more expressive type system, built-in string support,
and a component-based development model. Known for the **BlackBox Component Builder**
IDE and its novel approach to GUI construction using editable forms linked to exported
variables and procedures.

**Features of interest:**
- Minimal language with carefully chosen extensions over Oberon-2
- Component-oriented programming model
- Influenced Compact Pascal's design philosophy (already cited in the white paper)

**Reference:** https://en.wikipedia.org/wiki/Component_Pascal

## Active Oberon

**Origin:** ETH Zürich
**Lineage:** Oberon → Active Oberon

Extends Oberon with active objects, operator overloading, and exception handling.
Active objects encapsulate threads — each object can have a body that executes as a
concurrent activity. This is the direct ancestor of Zonnon's active object model.

**Features of interest:**
- Active objects as a concurrency primitive
- Operator overloading in the Oberon tradition
- Runs on the A2 (Bluebottle) operating system, which is written entirely in
  Active Oberon

**Reference:** https://en.wikipedia.org/wiki/Oberon_(programming_language)

## Lagoona

**Designer:** Michael Franz (student of Niklaus Wirth)
**Paradigm:** Component-oriented programming

An experimental language supporting component-oriented programming — decomposing
systems into logical components that communicate through message passing. Explores
the space between object-oriented and actor-based models.

**Features of interest:**
- Message-passing component model
- Academic exploration of post-Oberon ideas

## VSI Pascal (formerly DEC/Compaq/HP Pascal)

**Platform:** OpenVMS (VAX, Alpha, Itanium)
**Standards:** ISO 7185 + ISO 10206 (Extended Pascal) + own extensions

A production-quality Pascal compiler that fully implements Extended Pascal (ISO 10206),
one of very few compilers to do so. Extended Pascal adds conformant arrays, modules,
string schema types, and other features that address many of Pascal's well-known
limitations.

**Features of interest:**
- Full ISO 10206 implementation — a reference for what "standard extended Pascal"
  looks like in practice
- Production use in aerospace and defense (OpenVMS ecosystem)
- Compiler frontend written in BLISS

**Reference:** https://docs.vmssoftware.com/vsi-pascal-for-openvms-reference-manual/

## GNU Pascal (GPC)

**Standards:** ISO 7185 + ISO 10206 + Borland extensions

Aimed to implement the full Extended Pascal standard plus Borland compatibility.
Development has stalled, but it remains notable as one of the few attempts to support
both ISO standards and Borland dialect extensions in a single compiler.

**Features of interest:**
- Extended Pascal module system (separate from Borland units)
- Extended Pascal string schema types
- Extended Pascal conformant arrays

**Reference:** https://www.gnu-pascal.org/gpc/Welcome.html

## TMT Pascal

**Platform:** 32-bit DOS (protected mode), OS/2, Win32

First Borland-compatible Pascal compiler for 32-bit protected mode DOS. Notable for
adding **function and operator overloading** to a Borland-compatible dialect.

## Co-Pascal (Pascal-S extension)

Extension of Wirth's Pascal-S educational compiler with concurrency primitives. Part
of the tradition of using simplified Pascal implementations to teach concurrent
programming (alongside Pascal-FC and SuperPascal).

**Reference:** http://pascal.hansotten.com/niklaus-wirth/pascal-s/pascal-s-copascal/

## Pascal-XSC

**Origin:** University of Karlsruhe (KIT), Germany
**Released:** ~1991
**Website:** https://www2.math.uni-wuppertal.de/wrswt/xsc/pxsc.html

Pascal eXtension for Scientific Computation. Extends Pascal with **interval arithmetic**
and **verified numerical computing** — arithmetic operators that deliver results
guaranteed to differ from the exact answer by at most one rounding.

**Features of interest:**
- Predefined types for real intervals, complex numbers, complex intervals, and
  corresponding vectors and matrices
- Operators with guaranteed maximum accuracy (1 ULP)
- Automatic result verification for numerical algorithms
- Problem-solving routines for linear/nonlinear systems, differential/integral equations
- Successor: C-XSC (C++ library with the same capabilities)

This is relevant as an example of domain-specific type system extensions to Pascal for
scientific computing — complementary to Vector Pascal's SIMD approach.

**Reference:** R. Klatte et al., *PASCAL-XSC: Language Reference with Examples*,
Springer, 1992. https://link.springer.com/book/10.1007/978-3-642-77277-1

## Observations

Several patterns emerge from surveying Pascal dialects:

1. **Concurrency is the most common extension direction.** Concurrent Pascal, Joyce,
   SuperPascal, Pascal-FC, IP Pascal/Pascaline, Active Oberon, and Zonnon all add
   concurrency. The approaches range from monitors (Concurrent Pascal, Pascaline)
   to CSP channels (Joyce, SuperPascal) to active objects (Active Oberon, Zonnon).

2. **Module systems vary widely.** Turbo Pascal units, ISO 10206 modules, Oberon's
   minimal modules, Pascaline's uses/joins/share, and Zonnon's four-unit-kind system
   all solve the same problem differently.

3. **Dynamic arrays are a perennial need.** Pascaline, Extended Pascal, Free Pascal,
   and Delphi all had to add dynamic arrays. Pascaline's approach (dynamic arrays as
   containers for static arrays) is the most backward-compatible.

4. **The Wirth line (Oberon and descendants) favors minimalism;** the practical line
   (Delphi, Free Pascal, Pascaline) favors feature accumulation. Both approaches
   have produced useful languages.
