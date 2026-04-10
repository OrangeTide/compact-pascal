# PS-algol: Persistent S-algol

## Language Design

PS-algol (Persistent S-algol) is the first language in a family that introduces persistence as
a property of data. Designed by M.P. Atkinson, P.J. Bailey, K.J. Chisholm, W.P. Cockshott,
and R. Morrison at the University of Edinburgh and University of St Andrews, first published
in 1983.

### Design Principles

The core hypothesis: persistence should be addable to an existing language with minimal
change. The programmer learns the language normally and gets persistence at little extra cost.

Three design principles for persistent data:
1. **Persistence independence** — the persistence of a data object is independent of how the
   program manipulates it
2. **Persistence data type orthogonality** — all data types should be allowed the full range
   of persistence (following data type completeness)
3. **Persistence identification independence** — how persistence is provided/identified at
   the language level is independent of the choice of data objects

### The Persistence Spectrum

Data persistence exists on a spectrum:
1. Transient results in expression evaluation
2. Local variables in procedure activations
3. Own variables, globals, heap items (extent differs from scope)
4. Data that exists between executions of a program
5. Data that exists between versions of a program
6. Data that outlives the program

Categories 1–3 are supported by programming languages; 4–6 by DBMSs. PS-algol supports
all six categories.

### Base Language: S-algol

S-algol stands between Algol W and Algol 68 taxonomically. Designed using three principles
from Strachey and Landin:
1. The principle of correspondence
2. The principle of abstraction
3. The principle of data type completeness

The S-algol universe of discourse:
- Scalar types: `int`, `real`, `bool`, `string`, `pic`, `file`
- For any type T, `*T` is a vector of T
- `pntr` is a structure with any number of fields and any type per field

Unusual features: strings as a simple data type, pictures as compound data objects, and
runtime checking of structure classes (a `pntr` may roam freely over structure classes;
field access is checked at runtime).

### Persistence API

PS-algol is implemented as standard functions added to S-algol — the compiler itself was
barely changed. All persistence work is done by the runtime.

```
procedure open.database(string database.name, mode, user, password -> pntr)
procedure get.root(pntr database -> pntr)
procedure set.root(pntr old.root, new.root)
procedure commit
procedure abandon
procedure close.database(pntr root.value)
```

Plus an associative store (B-tree tables):
```
procedure table(-> pntr)
procedure lookup(pntr table; string key -> pntr)
procedure enter(pntr table, value; string key -> pntr)
procedure scan(pntr table, environment; (pntr, pntr, string -> pntr) user -> pntr)
```

Persistence is identified by reachability from the database root (like garbage collection
identifies liveness). `set.root` makes a subgraph persistent; `commit` writes it to the store.

### Example Program (from paper appendix)

```salgol
structure person( string name, phone.no ; pntr addr )
structure address( int no ; string street, town )
write "Name : " ;           let this.name = read.a.line
write "Phone number : " ;   let this.phone = read.a.line
write "House number : " ;   let this.house = readi
write "Street : " ;         let this.street = read.a.line
write "Town : " ;           let this.town = read.a.line
let p = person(this.name, this.phone, address(this.house, this.street, this.town))
let db = open.database( "Address.list", "write", "Ron", "Ann" )
if db = nil then write "Invalid opening of a database" else
begin
    enter( this.name, get.root( db ), p )
    commit
end
```

### Results

Programs written in PS-algol showed ~3x reduction in source code size compared to
equivalent programs in Pascal with explicit database calls (implementing DAPLEX). Coding
time was also reduced by a similar factor.

## Persistent Heap Algorithms

From: Atkinson, Chisholm, Cockshott, Marshall, "Algorithms for a Persistent Heap,"
*Software — Practice and Experience*, Vol. 13, pp. 259–271, 1983.

### The Portable S-Code Interpreter

S-algol generates intermediate S-code. The interpreter was written in IMP77 (chosen over
assembler for portability, over Pascal for inline assembler access). The interpreter has ~1500
lines of code with a few dozen lines of assembler in the main instruction fetch loop.

Modules: instruction fetch, I/O, instruction execution, initialization, heap.

Ported to: Z80, PDP 11, VAX, Perkin Elmer 3220. VAX port took 2 man-days.

### Pointer Representation: LONs and PIDs

Two forms of pointers:
- **LON** (Local Object Number) — index into an array holding actual RAM addresses
- **PID** (Persistent IDentifier) — 32-bit database token from the Chunk Management System (CMS)

Both are 32-bit words. PIDs are distinguished by having the sign bit set (bit 31 = 1).
The remaining 31 bits are a CMS token referencing a chunk of data.

### PIDLAM (PID-to-Local Address Map)

All addressing of local heap objects goes through the PIDLAM, a table indexed on LONs that
stores for each object:
- Address on the heap (local address, `la`)
- Database PID
- LI flag (Local or Imported)
- GC flag

PID-to-LON lookup uses a hash table over the PIDLAM as a cache. When a PID is dereferenced:
1. Hash lookup in PIDLAM
2. If found: return local address
3. If not: load object from database into heap, create PIDLAM entry

Per-object overhead: 14 bytes (4 header + 2 LON + 2 local address + 4 PID + 1 flags + 1 hash).

### Heap Object Formats

Three object types, all tagged:

**Vectors:** Two header words — Word 0 has pointer flag (1 bit), type (4 bits: 0 for vector),
size in bytes (27 bits). Word 1 has lower bound.

**Strings:** Same header as vectors but type = 2. Size field = number of characters (not
including header/padding).

**Structures:** Two-word header like vectors but type = 15. Word 1 is a "trademark" —
an index into a structure table describing size and number of pointer fields per class.
Pointer fields are concentrated at the start of the structure for GC efficiency.

### Garbage Collection

Compacting mark-sweep collector. The interpreter maintains two stacks:
- Main stack: integers, reals, booleans
- Pointer stack: all variables referencing strings, vectors, structures

GC roots: pointer stack + imported objects + string table (predeclared single-char strings).

Mark phase uses the PIDLAM to hold mark bits and stores each item's LON at the end of
the object in RAM (optimization for the compaction phase). Compaction is a linear scan that
copies marked items down and updates PIDLAM local addresses.

If GC cannot free enough space, the entire heap is purged to the database (all objects
converted to PIDs and sent back).

### Transaction Commit ("Close Down")

Three ways a program terminates:
1. Reaching the end → commit
2. `abort` statement → abandon (rollback, very efficient)
3. `commit` procedure → commit

During execution the runtime maintains:
- **Nlist** (New list): PIDs of objects created this run
- **Olist** (Old list): PIDs of objects imported from the database

Commit algorithm (`close`):
1. Mark all reachable from imports
2. Send all back to database
3. Pull Nlist into RAM
4. Initialize heap with remaining store
5. **Thresh**: separate persistent from temporary items on the Nlist

Threshing uses breadth-first (widthwise) traversal of the reachability tree from the Olist,
not depth-first — depth-first risks filling the heap before marking all dependents.

### Complexity

The threshing algorithm is O(N²) worst case where N is the Nlist size. Could be improved
to O(N log N) by restructuring the Nlist as a binary tree. The linear component from
database fetches dominates for small N; the quadratic scan cost dominates for large N.

Measured on VAX 11/780:
- Transaction A (create 1000 objects of 50 bytes each): 1s CPU, 100 page faults, 5s elapsed
- Transaction B (read tree of 1000 objects): 0.15s CPU, 0 page faults, 0.5s elapsed

## IBM PC/AT Implementation

### Overview

This is a compiler, integrated editor/IDE, and runtime system for **Persistent S-algol (PS-algol)**, a dialect of S-algol with persistent storage capabilities. It targets **IBM PC/AT compatibles** running **MS-DOS**, generating 8086 machine code. The system was written primarily by **W. Paul Cockshott** with contributions from **P. Balch**, beginning in **October 1986**, with a major restructuring into Turbo Pascal units around **September 1988**.

The codebase has two historical layers visible in `sc.pas`:
1. An older **Turbo Pascal 3** version using `{$i ...}` include-file compilation (single-program model with overlays).
2. A later **Turbo Pascal 5+** version restructured into proper `unit` modules with conditional compilation (`{$ifdef assembler}` toggles between an external A86 assembler pass and a built-in direct-to-binary assembler).

The persistence layer is provided by an external **"7layer" system** -- a layered persistent object store that manages heaps, PIDs (persistent identifiers), indexes, and transactions via files configured in `7layer.sys`.

---

## Architecture

```
Source (.s files)
       |
  [FSM lexer] --> [DLB token lookup] --> [Syntax analyser] --> [Code generator]
       |                                      |                      |
   fsm.pas                               sasyn.pas            sagen.pas (direct)
                                                               or cgendum (via A86)
       |
  [Assembler]  -->  .out object file
   assemble.pas        |
       |          [Dynamic linker + Runtime]
       |               |
       +--------> Execution (pslib.c + C libraries)
```

---

## Component Inventory

### Compiler Front-End (Turbo Pascal)

| File | Role |
|------|------|
| `sc.pas` | **Main program** -- the top-level compiler/IDE driver. Contains both the old include-file version and the newer unit-based version. |
| `salgol.pas` | Older monolithic main program (Turbo Pascal 3 era), uses `{$i}` includes. |
| `fsm.pas` | **Finite State Machine lexer** -- first-level lexical analysis. Splits text buffer into raw lexemes (identifiers, numbers, strings, operators, etc.). |
| `dlb.pas` | **De La Brandais tree tokeniser** -- converts raw lexemes into integer token codes using a trie structure. Provides `next_symbol`, `have`, `mustbe` entry points. |
| `sasyn.pas` | **Syntax analyser** -- single-pass top-down recursive descent parser for PS-algol. One procedure per production rule. Calls the lexer, symbol table, and code generator. Supports runtime syntactic extensions via a rule table. |
| `symtab.pas` | **Symbol table** -- maps identifiers to type descriptors. Handles lexical scoping, type checking (`eq`, `match`, `coerce`, `balance`), parameter lists, and block-level management. |
| `idtypes.pas` | **Type system declarations** -- defines `typerec`, `idrec`, `namedesc`, `paramref` and the S-algol type constants (int, real, bool, string, pntr, file, proc, vector, structure, etc.). |
| `symbols.pas` | **Lexeme enumeration** -- the `lexeme` enumerated type listing all S-algol terminal symbols. |
| `lexemes.def` | **Lexeme definition file** -- text file listing all keywords and operators, read by `dlb.pas` to build the token lookup tree. |
| `errors.pas` | **Compiler error handling** -- error reporting, `ErrorReturn` longjmp-style mechanism, heap error trapping, and runtime error handler. |
| `reader.pas` | **File reader** -- loads source files into text buffers for the lexer. |
| `reals.pas` | **IEEE float conversion** -- converts Turbo Pascal 6-byte reals to 8-byte IEEE 754 double-precision format for the target machine. |
| `env.pas` | **Environment variable lookup** -- reads DOS environment (e.g., `PSDIR`) to locate runtime libraries and tools. |

### Compiler Back-End / Code Generation

| File | Role |
|------|------|
| `sagen.pas` | **Direct code generator** -- generates abstract machine instructions (opcodes) directly into an internal representation. Used when `{$ifndef assembler}`. Defines the full code generation API (`start_program`, `end_program`, `epilogop`, `prologop`, `jumpop`, `call_proc`, `makevec`, etc.). |
| `cgen.pas` | **Code generator constants** -- older version defining the lexeme enum and code generation constants (used in the include-file build). |
| `cgengen.pas` | **Code table generator tool** -- standalone program that reads `opcodes.def` and produces: (a) an assembly language program, and (b) a Pascal unit defining types/tables for the abstract machine instruction set. |
| `opcodes.def` | **Opcode definition file** -- defines the abstract machine instructions with operand classes (0-7: no operand, 16-bit, 16+8-bit, string, byte, relative branch, byte-relative, absolute label). |
| `opcodes.pas` | **Generated opcode unit** -- Pascal unit with the `opcode` enumeration (output of `cgengen.pas`). |
| `assemble.pas` | **Built-in assembler** -- two-pass assembler that converts abstract machine pseudo-instructions into 8086 machine code and writes a `.out` binary. Used when `{$ifndef assembler}`. |
| `mkctab.pas` | **Character class table generator** -- standalone tool that generates `classtab.cmp`, the character classification table used by the FSM lexer. |

### IDE / Editor (Turbo Pascal)

| File | Role |
|------|------|
| `editor.pas` | **Text editor** -- full-screen text editor ("Analogue Editor Toolbox v2.00A") with undo, search/replace, block operations, and integrated compilation. |
| `editdecl.pas` | **Editor declarations** -- types, constants, and global variables for the editor (screen dimensions, colours, file paths, configuration, text buffer structures). |
| `edit_err.pas` | **Editor error handling** -- message line display, error message file lookup, `ErrorReturnHere`/`ErrorReturn` using inline x86 for setjmp/longjmp-style error recovery. |
| `screen.pas` | **Screen abstraction** -- low-level screen I/O (direct video memory access, keyboard input, cursor control). Supports CGA, EGA, VGA, Hercules, and AT&T 400. |
| `menu.pas` | **Menu system** -- pull-down menus, menu bars, gauge items, help screen display. |
| `mouse.pas` | **Mouse driver** -- INT 33h mouse interface with click/drag/mode detection. |
| `control.pas` | **Menu command handler** -- wires menu selections to editor/compiler actions (compile, run, file operations, search, options). |
| `dir.pas` | **Directory services** -- file browser, directory listing, file deletion. |
| `compile.pas` | **Compilation driver** -- `compile_prog` and `run_prog` procedures that orchestrate compilation from the editor, invoke the assembler, and execute the result. |
| `compiler.msg` | **Compiler error messages** -- numbered message file for I/O and editor errors. |
| `editor.msg` | **Editor help/error messages**. |

### Runtime System (C + Assembly)

| File | Role |
|------|------|
| `pslib.c` | **PS-algol runtime library** -- the main runtime: DEFPIDREG (process init), WRITEP/WRITES/WRITEI/WRITER (output), READI/READR/READS (input), MAKEVEC (vector allocation), SUBSTR/CONCAT (string ops), dynamic binding, segment management, error handling. Depends on the 7layer persistent store. |
| `main.c` | **C main entry point** -- initialises the 7layer store, calls `SAMAIN()` (the compiled S-algol program's entry), commits transactions. |
| `filelib.c` | **File I/O library** -- OPEN, CREATE, READBYTE, WRITEBYTE, etc. for S-algol file operations. Uses the 7layer persistence layer. |
| `mathlib.c` | **Math library** -- SIN, COS, SQRT, EXP, ATAN, TAN, LN, TRUNCATE, Hash. Wraps C math.h for S-algol. |
| `crtlib.c` | **CRT/video library** -- SGOTOXY, SWHEREX, SWHEREY, SGETCH, SLINE, mouse functions. Wraps video BIOS. |
| `graphics.c` | **Graphics library** -- pixel-level drawing for Hercules, VGA, and text modes. Line drawing, character rendering, screen clearing. |
| `raster.c` | **Raster operations** -- bitwise raster copy for EGA/VGA frame buffer manipulation. |
| `link.c` | **Dynamic linker** -- resolves S-algol `alien` procedure calls to C functions at runtime. Patches INT 18h call sites with direct FAR CALLs after first resolution. |
| `procdef.c` | **Procedure definition table** -- maps C function addresses to their S-algol names for the dynamic linker. This is the FFI registration table. |
| `linker.asm` | **Linker interrupt handler** -- INT 18h handler that invokes `link.c`'s LINK function, then returns to re-execute the now-patched call site. |
| `exec.pas` / `exect.pas` | **DOS EXEC wrapper** -- launches child processes (assembler, compiled programs) from within the IDE using DOS INT 21h function 4Bh. Manages memory allocation for child process. `exect.pas` is a variant with persistence support (`get_ps_return_code` via INT 18h). |
| `salib.h` | **Runtime header** -- C struct definitions for S-algol runtime types (string, intvec, realvec, pidv, saframe). |
| `link.h` | **Linker header** -- declares the `identifier` struct for the procedure name table. |
| `string.c` | **String utility** (minimal). |

### Persistence Layer (External)

| File | Role |
|------|------|
| `7layer.sys` | **7layer configuration** -- paths for the persistent store's index file, heap file, PID-LAM file, and machine ID. |

The 7layer system is an external library providing:
- **Layer 3**: Persistent heap and object management (PIDs, object allocation, commit/abort)
- **Layer 4**: Higher-level persistent data structures
- **Layer 5**: Additional services

Header files referenced: `layer3.h`, `layer4.h`, `layer5.h`, `bases.h`.

### Assembly Support Files

| File | Role |
|------|------|
| `opcodes.asm` | Generated 8086 opcode implementations (code templates for each abstract machine instruction). |
| `graphics.asm` | Low-level graphics primitives in x86 assembly (Hercules adapter support). |
| `iolib.asm` | I/O library assembly stubs. |
| `putloop.asm` | Pixel output loop in assembly. |
| `enter.asm` | Stack frame entry code. |

### Sample S-algol Programs

| File | Description |
|------|-------------|
| `seive.s` | Sieve of Eratosthenes -- finds prime numbers using a boolean vector. |
| `mandel.s` | Mandelbrot set plotter -- uses VGA graphics and alien C procedures. |
| `dbtest.s` | Persistent database demo -- creates/opens/queries a persistent table using structures and file I/O. |
| `menu.s` | Menu library in S-algol. |
| `menulib.s` | Menu library support. |
| `menuseg.s` | Persistent menu segment. |
| `segdemo.s` | Segment/persistence demo. |
| `mathlib.s` | Math library declarations for S-algol (alien procedure bindings). |
| `strlib.s` | String library declarations. |
| `rastrlib.s` | Raster library declarations. |
| `filelib.s` | File library declarations. |
| `tablelib.s` | Table library declarations (empty). |

### Other / Build Artifacts

| File | Role |
|------|------|
| `a86.com` | A86 assembler binary (Eric Isaacson's 8086 assembler, used as external pass-2). |
| `salib.8` | A86 macro library for the S-algol abstract machine instruction set. |
| `iolib.8` | A86 macro library for I/O operations. |
| `classtab.cmp` | Generated character classification table (output of `mkctab.pas`). |
| `s.exe` | Compiled S-algol system binary (84KB). |
| `sc.exe` | Compiled S-algol compiler+IDE binary (141KB). |
| `tbasic.exe` | Appears to be a copy of s.exe (same size). |
| `s.asm` | Compiler output file (assembly, currently empty). |
| `s.lis` | Listing file (currently empty). |
| `SEIVE.OUT` | Compiled output of seive.s. |
| `menuseg.out` | Compiled menu segment. |
| `logfile` | Empty log file. |
| `turbo.msg` | Turbo Pascal runtime error messages. |
| `acker.c` | Ackermann function test in C. |
| `checkop.c` | Opcode checking test in C. |
| `exec.c` | Small C exec wrapper. |
| `mouse.c` | Minimal mouse test in C. |
| `asmtest.pas` | Assembler unit test. |

---

## Key Design Patterns

1. **Conditional compilation**: `{$ifdef assembler}` switches between two code generation paths -- one producing A86 assembly text, the other directly emitting binary via the built-in `assemble.pas`.

2. **Setjmp/longjmp error recovery**: `ErrorReturnHere` (in `edit_err.pas`) saves the stack pointer and return address using inline x86 assembly. `ErrorReturn` restores them to unwind the stack on compiler errors, returning control to the editor.

3. **Dynamic linking via INT 18h**: Compiled S-algol programs use `INT 18h` for first-call resolution of `alien` procedures. The linker interrupt handler (`linker.asm` + `link.c`) patches the call site with a direct FAR CALL, so subsequent calls go directly to the C function.

4. **Persistent identifiers (PIDs)**: The 7layer store provides garbage-collected persistent objects addressed by PIDs rather than raw pointers. The runtime (`pslib.c`) translates between S-algol's pointer type and PIDs.

5. **Text buffer model**: Source code lives in a flat character array (`textbuffer`) with start/finish cursors. The FSM lexer scans this buffer directly. The editor and compiler share the same buffer structure.

---

## Component Dependencies (for extraction planning)

```
editdecl  (standalone - depends only on Crt, Dos, Screen)
  |
screen    (standalone - depends only on Crt, Dos, Graph)
  |
fsm       (depends on editdecl)
  |
env       (depends on editdecl)
  |
dlb       (depends on errors, editdecl, fsm, env)
  |
idtypes   (depends on editdecl, errors, dlb)
  |
reals     (standalone)
  |
opcodes   (standalone - generated)
  |
assemble  (depends on errors, opcodes, editdecl)
  |
sagen     (depends on reals, editdecl, errors, fsm, dlb, idtypes, opcodes, assemble)
  |
symtab    (depends on editdecl, errors, idtypes, dlb, sagen)
  |
sasyn     (depends on editdecl, errors, fsm, reader, dlb, idtypes, sagen, symtab)
  |
compile   (depends on everything above + editor units)
```

### Suggested Extraction Order (compiler core, no IDE)

1. **Lexer group**: `editdecl` (data types only), `fsm`, `dlb`, `symbols`/`lexemes.def`
2. **Type system**: `idtypes`, `reals`
3. **Symbol table**: `symtab`
4. **Code generation**: `opcodes`/`opcodes.def`, `sagen`, `assemble`
5. **Parser**: `sasyn`
6. **Runtime library**: `pslib.c`, `filelib.c`, `mathlib.c`, `link.c`, `procdef.c`
7. **IDE** (optional): `editor`, `menu`, `mouse`, `screen`, `control`, `dir`

The compiler core (steps 1-5) is roughly 10 Pascal units totalling ~2,600 lines and can be extracted independently of the IDE and runtime.

## References

- M.P. Atkinson, P.J. Bailey, K.J. Chisholm, W.P. Cockshott, R. Morrison, "PS-algol: A
  Language for Persistent Programming," Proc. 10th Australian National Computer
  Conference, Melbourne, 1983, pp. 70–79.
- M. Atkinson, K. Chisholm, P. Cockshott, R. Marshall, "Algorithms for a Persistent Heap,"
  *Software — Practice and Experience*, Vol. 13, pp. 259–271, 1983.
- R. Morrison, *S-algol Language Reference Manual*, University of St Andrews CS/79/1, 1979.
- A.J. Cole, R. Morrison, *An Introduction to Programming with S-algol*, Cambridge
  University Press, 1982.
- P.J. Bailey, P. Maritz, R. Morrison, *The S-ALGOL Abstract Machine*, Dept of
  Computational Science, University of St Andrews, 1980.
- M.P. Atkinson, K.J. Chisholm, W.P. Cockshott, "CMS — A Chunk Management System,"
  *Software — Practice and Experience*, Vol. 13, pp. 273–285, 1983.
- M.P. Atkinson, W.P. Cockshott, K.J. Chisholm, "NEPAL — The New Edinburgh Persistent
  Algorithmic Language," DATABASE Infotech State of the Art Report, 9,8 pp. 299–318, 1982.
- Local papers: ~/Documents/Papers/PS-Algol/ (ABC+83b.pdf, Algorithms_for_a_Persistent_Heap.pdf)
- Local implementation: ~/Documents/Papers/PS-Algol/ibmatsalgol.zip
