# Security Policy

## Reporting a Vulnerability

Report security issues privately through
[GitHub Security Advisories](https://github.com/OrangeTide/compact-pascal/security/advisories/new),
which keeps the report between you and the maintainers until there is a fix.

Please do not open a public issue for a vulnerability. Please do include:

- What an attacker can do, stated as an outcome rather than as a code smell
- A minimal Compact Pascal program or Rust host that demonstrates it
- The version, from the release you used or the commit you built
- The runtime you used, and whether it reproduces under another one

### What to expect

This is a small project maintained by one person. There is no on-call
rotation and no service-level agreement, and saying so plainly is more useful
than promising a response time that will not be met.

| Stage | Target |
|---|---|
| Acknowledgment | Within one week |
| Assessment, with a decision on whether it is a vulnerability | Within two weeks |
| Fix or a public explanation of why there will not be one | Within 90 days |

If you have not heard back within two weeks, please send a reminder through the
same channel. Silence means the message was missed, not that the report was
dismissed.

You are welcome to disclose publicly after 90 days from your report, whether or
not there is a fix. If a fix lands earlier, coordinated disclosure at that
point is preferred.

Credit is given in the advisory and in `CHANGELOG.md` unless you ask otherwise.
There is no bug bounty.

## Threat Model

Knowing what counts as a vulnerability requires knowing what the project claims
to protect. Compact Pascal is an embeddable compiler, so its security story is
about the boundary between a host application and the Pascal code it runs.

### In scope

**Escaping the WASM sandbox.** A compiled program that reads or writes host
memory, reaches the filesystem or network, or invokes host capability that was
not registered as an import. This is the central claim and the most serious
class of report.

**Compiler memory corruption from source input.** The compiler is itself a
WASM program. Source that makes it write outside its own linear memory, or
that makes it emit a module which then escapes the sandbox, is in scope. A
compiler that traps or exits with a diagnostic on bad input is behaving
correctly, not vulnerably.

**Emitting a module that does not match the source's semantics** in a way that
crosses a security boundary. Miscompiling a bounds check away, for instance.

**Host API misuse that the API invites.** If the documented, obvious use of an
API in `EMBEDDING-GUIDE.md` leaves the host exposed, that is a problem with the
API, not with the reader.

**Include resolution reaching outside its base directory** when the host used
`compile_with_includes` with a base directory, since that is the boundary the
call is meant to draw.

### Out of scope

**A guest corrupting its own memory.** Within its own linear memory, a Pascal
program can corrupt its own data through a stale pointer or an out-of-range
index. This is a language property, documented in the reference under Defined
and Undefined Behavior, and the `{$S+}` and `{$R+}` checks exist to catch it in
practice. The sandbox is not weakened by it.

**A guest consuming time or memory without bound.** A program can loop forever
or grow memory until the host refuses. `Limits` exists for this, and a host
that runs source it did not write and sets no limits has made a choice.
Reports that a specific input is unusually expensive are welcome as ordinary
issues.

**Capability that a host granted deliberately.** If a host registers an import
that opens a file by name, a guest opening files is the host's design, not a
vulnerability in this project.

**Compiling hostile source being as dangerous as running it.** The compiler
executes while it compiles, in the same sandbox. This is stated in the
embedding guide and is not a defect.

**The playground's client-side sandbox** beyond what the browser's own
WebAssembly isolation provides.

## Supported Versions

Only the latest release receives fixes. The project has not reached 1.0 and
does not maintain release branches.

## Hardening Notes for Hosts

If you run Pascal source that you did not write:

- Set `Limits` with both `fuel` and `memory_bytes`. Neither is on by default.
- Register the smallest set of imports that the workload needs. Every import
  is capability handed across the boundary.
- Resolve includes against a fixed directory, or expand them yourself. Joining
  an untrusted path is how a sandbox becomes a file reader.
- Leave `stack_checks` on. It is the default, and turning it off converts a
  trap into silent memory corruption inside the guest.
- Treat compilation as execution when budgeting time and memory.
