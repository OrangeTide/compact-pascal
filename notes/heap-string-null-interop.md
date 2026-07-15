# Phase 6b heap string: length + null for PChar interop

Status: pointer note, July 2026, authored from the skjegg project (as the
methods/interfaces spec review was). The full design lives in the
Excelsior series at `skjegg/excelsior/string-repr.md`; this note records
the part that binds Compact Pascal so it is discoverable when Phase 6b is
planned.

Made by a machine. PUBLIC DOMAIN (CC0-1.0)

## The recommendation

Short strings stay exactly as they are: the Turbo Pascal `[length
byte][<=255 bytes]` layout, no null terminator, value-copied. TP
compatibility fixes that, and this note does not touch it.

The **Phase 6b heap string** (pointer + length, no 255-char cap) is where
C interop wants a decision, and the recommendation is to make an owned
heap string **length-terminated and null-terminated at once**: store the
length and also write a trailing `\0`. Then:

- `PChar(s)` on an owned heap string is an O(1) cast, not a copy, exactly
  as Delphi/FPC `AnsiString` already is.
- A **substring** of a heap string is a length-only **view**: it has no
  terminator (the byte past its end belongs to the parent), so it must be
  **materialized** (copied into a fresh terminated buffer) before it can
  become a `PChar`. The compiler inserts that copy at exactly that point.

## Why it fits CP's discipline

The owned-versus-view distinction is a property of the type, known at the
declaration, so it is single-pass verifiable, the through-line the
methods/interfaces review named as the language's identity. Kept to two
levels (owned buffer versus view), it adds no inference and no second
pass. The termination guarantee travels in the type; there is no runtime
tag, because heap strings are not mutated in place under aliasing.

Embedded NUL: the length stays authoritative, and a `PChar` cast
truncates the C view at the first interior `\0` (the standard C caveat).
Rust's `CString`, which forbids an interior NUL, is the recorded stricter
path if a real interop surface ever needs the guarantee.

This is the second convergence between the two projects (after
compiler-generated interface files): both independently reach
dual-terminated owned strings. See `skjegg/excelsior/string-repr.md` for
the survey (Zig sentinel slices, Delphi AnsiString, Rust CStr/CString, Go
as the cautionary copy-at-every-boundary case), the full design, and the
decisions.
