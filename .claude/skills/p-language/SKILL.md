---
name: p-language
description: P language syntax, semantics, and idioms for state-machine models of distributed and concurrent systems. Use whenever reading, writing, or reviewing .p files, P machines, spec monitors, test drivers, or .pproj projects, and when answering a question about P syntax.
---

# P Language

P models a system as communicating state machines and checks it with `p check`. Write P as P, not as
C with different punctuation. The rules below are the ones that actually break builds.

Related skills: **p-project** (scaffold a project, design doc → model), **p-verify** (compile and
model-check), **p-debug** (fix compile errors and counterexamples).

## Hard rules

These are not style preferences. Each one is a compile error.

1. **Declaration and assignment are separate statements.** `var x: int = 0;` is illegal.
   Write `var x: int;` then `x = 0;`.
2. **All `var` declarations go at the top of their block** — a `fun` body, an `entry`/`exit` block, or an
   `on ... do { }` handler. Never after a statement, never inside a `while` or `foreach` body.
3. **A single-field named tuple *value* needs a trailing comma.** `(requestId = 42,)`. The type annotation
   does not: `type tReq = (requestId: int);`. Omitting it gives
   `no viable alternative at input 'requestId=42)'`, the single most common P compile error.
4. **Event payloads must be named user-defined types.** Declare the type, then the event:
   `type tReq = (id: int, src: machine); event eReq: tReq;`. An inline tuple in the `event` declaration
   is invalid.
5. **Read payloads through handler parameters:** `on eReq do (p: tReq) { ... }`, or
   `entry (p: tReq) { ... }`. There is no `receive()` *function*. There is a blocking `receive`
   *statement*, used inside a function to await specific events:
   `receive { case eLockGranted: (r: tResp) { ... } }` — everything else is deferred while it blocks.
6. **`!` needs parentheses around a membership test:** `!(k in m)`. There is no `!in` or `not in`.
7. **Sequences append by index-value pair:** `s += (sizeof(s), v);`. Sets take the value alone:
   `st += (v);`. There is no `append()`.
8. **Collections start empty.** Do not reassign them to a default. Use `default(T)` only for scalars and
   tuples.
9. **A named `entry` function takes at most one parameter. `exit` functions take none.**
   Spec monitor `entry` functions take none either.
10. **Inside a spec monitor, `this`, `new`, `send`, `announce`, `receive`, `$`, `$$` and `pop` are all
    forbidden.** A monitor observes; it does not act. To key state per machine, use
    `map[machine, T]` with the machine taken from an event payload.
11. **`};` is required after a `module`, `test`, `enum` or `type` declaration and wrong after a code
    block.** `state S { ... }` takes no semicolon.
12. **Every state must handle, `defer`, or `ignore` every event that can reach it.** An unhandled event is
    a runtime failure the checker will find.

## P does not have

`switch` (use `if`/`else if`), `const` (use a zero-argument function: `fun MAX(): int { return 10; }`),
`is`, `self`, `indexOf()`, `to string` (use `format("{0}", x)`), `append()`, `receive()` as a function,
standalone `interface` declarations, string concatenation with `+`, and sequence concatenation
(`s1 + s2` is not a thing — append in a loop).

It *does* have `keys(m)` and `values(m)`, both returning a `seq`. PeasyAI's `p_nuances.txt` claims
`values()` is unsupported; that line is wrong — `values` is a reserved keyword with its own section in
P's type guide.

`this` exists in a machine but not in a monitor, and is not used to reach a machine's own variables —
reference them by name.

## Reserved keywords

Never use as an identifier:

```
var type enum event on do goto data send announce receive case raise machine state hot cold start
spec module test main fun observes entry exit with union foreach else while return break continue
ignore defer assert print new sizeof keys values choose format if halt this as to in default
Interface true false int bool float string seq map set any
```

## References

Load only what the task needs.

| File | Covers |
|---|---|
| [references/syntax-core.md](references/syntax-core.md) | Types, tuples, collections, enums, events, statements, expressions |
| [references/machines.md](references/machines.md) | State machines, handlers, `defer`/`ignore`, and machine configuration (Pattern A vs Pattern B) |
| [references/specs-monitors.md](references/specs-monitors.md) | Spec monitors, safety vs liveness, `hot`/`cold` states |
| [references/tests-modules.md](references/tests-modules.md) | Test declarations and the module system, in both styles used here |
| [references/idioms.md](references/idioms.md) | Request-response, broadcast, quorum, timer, failure injection, and protocol patterns |
| [references/pitfalls.md](references/pitfalls.md) | Symptom → cause → fix for the mistakes that recur |

## Before handing over any `.p` file

Run the static checker. It is stdlib-only Python, needs no API key, and catches most of the above:

```bash
python3 -I .claude/skills/p-language/scripts/validate_p.py PATH/TO/File.p --project PATH/TO/PROJECT
```

`--project` is the directory whose `*.p` files form the cross-file context, which is what lets it check
undeclared types and events, duplicate declarations, and named-tuple construction at `new`/`send` sites.
Omit it and it walks up to the nearest `.pproj`. For a shared-`Common/` layout, point it at the directory
*above* the `.pproj` so `../Common/*.p` is in scope.

Exit status is 1 if anything ERROR-severity remains. Fix errors before compiling; warnings are worth
reading but are sometimes legitimate.

`--fix` applies a curated set of safe rewrites in place and refuses to write a file whose comments or
brace balance changed. `--fix-all` adds two rewrites that change valid code — review the diff.
A clean run is not a substitute for `p compile`; see **p-verify**.
