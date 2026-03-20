# Joyce

**Designer:** Per Brinch Hansen
**Released:** 1987
**Paradigm:** Concurrent, imperative, structured
**Influenced by:** CSP, Pascal, Concurrent Pascal
**Influenced:** SuperPascal
**Wikipedia:** https://en.wikipedia.org/wiki/Joyce_(programming_language)

## Core Concept

Joyce is a secure concurrent programming language based on a small subset of Pascal,
extended with features from Hoare's Communicating Sequential Processes (CSP). Its
central idea is the **agent** — a concurrently executed process that communicates only
through typed channels, with no shared variables. Joyce removed a major limitation of
CSP by introducing **parallel recursion**: agents can dynamically and recursively
activate subagents.

Joyce was designed primarily as a teaching tool for distributed computing.

## Key Features

### Agents

An agent is a procedure-like construct that executes concurrently. Agents activate
subagents dynamically; a creator agent cannot terminate until all its subagents have
terminated.

```pascal
agent process1(x, y: integer);
begin
  ...
end;

agent process2();
use process1;
begin
  process1(9, 17);
end;
```

Agent activation creates fresh copies of all local variables and copies formal
parameters to locals. Agents **cannot access variables of other agents** — they
communicate exclusively through channels. This restriction prevents race conditions
by construction.

### Typed Channels

Channels are created dynamically and have a typed **alphabet** defining what symbols
may be transmitted. Symbols can be typed messages or untyped signals:

```pascal
stream = [int(integer), eos];
```

Here `int(integer)` is a message carrying an integer value, and `eos` is a signal.

Channel creation uses the `+` operator on a port variable:

```pascal
var out: stream;
+out;  { create channel }
```

### CSP-Style Communication

Sending and receiving use `!` and `?` operators:

```pascal
out ! int(9)    { send }
out ! eos       { send signal }

in ? int(received)  { receive into variable }
in ? eos            { receive signal }
```

Communication is **synchronous** — a send blocks until a matching receive occurs.

### Polling (Guarded Alternatives)

Based on CSP's guarded commands. A polling statement selects among multiple possible
communications:

```pascal
poll
  in ? X -> x := x + 1 |
  in ? Y -> y := y + 1
end
```

### Recursive Agent Activation

Agents can recursively create subagents, enabling dynamic construction of communication
topologies like pipelines and trees. The sieve of Eratosthenes example from the
original paper demonstrates this elegantly — each sieve agent filters multiples of a
prime and recursively creates its successor.

### Security

Joyce is designed so that a compiler can detect all violations of language rules. The
restriction to channel-only communication (no shared variables) is the primary security
mechanism.

### Stack Allocation

Because concurrent agents don't follow LIFO activation patterns, Joyce uses a
tree-structured stack: new activation records are allocated at the top and linked to
their creator. Records are freed only when the agent terminates and is at the top of
the stack. This scheme is simple but can waste memory in some patterns. SuperPascal
improved on it.

## Significance

Joyce bridged the gap between CSP (a formal calculus) and a practical programming
language. Its agent model — isolated processes with typed channel communication — is
a precursor to the actor model that appears in Erlang and modern concurrent languages.

## References

- P. Brinch Hansen, "Joyce — A Programming Language for Distributed Systems,"
  *Software: Practice and Experience*, vol. 17, no. 1, pp. 29–50, 1987.
  http://pascal.hansotten.com/uploads/pbh/joyce.pdf
- P. Brinch Hansen, "The Joyce Language Report," *Software: Practice and Experience*,
  vol. 19, no. 6, pp. 553–578, 1989.
- P. Brinch Hansen, "A Multiprocessor Implementation of Joyce," *Software: Practice
  and Experience*, vol. 19, no. 6, pp. 579–592, 1989.
- Wikipedia: https://en.wikipedia.org/wiki/Joyce_(programming_language)
