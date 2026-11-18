# P syntax: types, collections, statements

Condensed from PeasyAI's `p_types_guide.txt`, `p_statements_guide.txt`, `p_enums_guide.txt` and
`p_events_guide.txt`. Every INCORRECT/CORRECT pair here is one that actually bites.

## Declarations

A P program is made of exactly seven kinds of top-level declaration: enums, user-defined types, events,
state machines, spec monitors, global functions, and modules. Nothing else is top level, and there are no
standalone `interface` declarations.

## Primitive types

`int`, `float`, `bool`, `string`, plus `machine` (a machine reference) and `event`.

```p
var i: int;  var f: float;  var s: string;  var b: bool;
i = 10;
f = 10.0;
s = "Failure!!";
b = (i == (f to int));        // `to` coerces
```

## User-defined types

```p
type tLookUpRequest = (client: machine, requestId: int, key: string);
```

Typedefs only name a shape; they do not create a distinct type. `tLookUpRequest` and an identically
shaped `tLookUpRequestX` are the same type to the compiler. A type name may not be a reserved keyword.

## Tuples and named tuples

```p
(1, "two", true)                 // positional tuple
(reqId = 10, key = "k")          // named tuple, multiple fields
(reqId = 10,)                    // single field — TRAILING COMMA REQUIRED
```

```p
// WRONG — missing trailing comma. Error: no viable alternative at input 'reqId=10)'
(reqId = 10)

// WRONG — a named-tuple type needs field names at the construction site
send server, eReadQueryResp, (query.accountId, balance[query.accountId]);
```

Both named and positional construction are valid for a named-tuple type. Field access is `x.fieldName`.

## Enums

```p
enum tWithDrawRespStatus { WITHDRAW_SUCCESS, WITHDRAW_ERROR }

enum tResponseStatus { ERROR = 500, SUCCESS = 200, TIMEOUT = 400 }
status = ERROR;                  // values are GLOBAL constants, referenced bare
assert (ERROR to int) == 500;
```

Enum values are global constants and must be unique program-wide. Reference them bare — there is no
`tResponseStatus.ERROR` qualified form.

## Events

Every payload must be a declared named type. An inline tuple in the `event` declaration is invalid.

```p
event ePing;                                            // no payload
type tRequest = (client: machine, requestId: int, key: string);
event eRequest: tRequest;                               // payload is a named type

// WRONG
event eRequest: (client: machine, requestId: int);
```

Event names must be unique and must differ from every type and enum name.

## Collections

`seq[T]`, `map[K, V]`, `set[T]`. All are **empty on declaration** — never reassign them to a default.

```p
// SEQUENCE — insert takes an (index, value) pair
s += (sizeof(s), v);          // append
s += (0, v);                  // prepend
s += (pos, v);                // insert at pos, 0 <= pos <= sizeof(s)
s -= (i);                     // remove BY INDEX, not by value
s[i]                          // index

// WRONG
s += (v);                     // missing index
s = s + (v,);                 // no + operator on sequences
s = append(s, v);             // no append() function
s -= v;                       // missing parens

// SET — value alone, in parens
st += (v);
st -= (v);
// WRONG: st += v;

// MAP
mp += (k, v);                 // insert; errors if k exists
mp[k] = v;                    // insert or update
mp -= (k);                    // remove by key
mp[k]                         // read
```

### Querying

```p
sizeof(c)                     // seq, map or set
keys(mp)                      // seq[K]
values(mp)                    // seq[V]
k in mp                       // key membership for a map; element membership for seq/set
!(k in mp)                    // negation NEEDS the parens. No !in, no "not in"
```

### Iteration

```p
var str: string;              // declared at the TOP of the function body
foreach (str in sq) { print str; }
foreach (k in keys(mp))  { mp[k] = 0; }

// WRONG — iteration variable not declared
foreach (str in sq) { print str; }
```

`foreach` enumerates a clone, so mutating the collection inside the loop is safe. A `while` loop works too
and is the common form when you need the index:

```p
i = 0;
while (i < sizeof(s)) { print s[i]; i = i + 1; }
```

Do not declare a `var` inside a `while` or `foreach` body — hoist it to the top of the enclosing block.

## Default values

```p
x = default(tRequest);
assert x.client == default(machine);
```

`int` → `0`, `float` → `0.0`, `bool` → `false`, `string` → `""`, collections → empty, `machine` → `null`.
Variables are already initialized to their default on declaration, so an explicit `default()` assignment is
usually redundant. Passing `default(set[machine])` as machine config is a common real bug: see
`p-project/references/wiring-review.md`.

## Universal types

`any` is the supertype of everything. `data` is the supertype of everything with no embedded `machine`
type — so `data` covers `(key: string, value: int)` but not `(key: string, client: machine)`.

## Statements

```p
x = expr;                               // assignment; never in a declaration
if (c) { } else if (c2) { } else { }    // no switch
while (c) { ... break; ... continue; }
return;  return expr;
assert c, "message";                    // message optional but worth writing
assert c, format("bad {0}", x);
print "literal";
print format("Hello {0} and {1}!", a, b);
```

### send

```p
send target, eRequest, (client = this, requestId = 1, key = "k");
```

Asynchronous and non-blocking: it enqueues onto the target's buffer. `target` must be a variable of
machine type. The payload must match the event's declared payload type exactly. Do not wrap a
single-field payload in a second tuple.

### new

```p
clients += (sizeof(clients), new Client((server = this, id = i)));
```

Config is a single value, so group multiple settings into one named tuple. See
`references/machines.md` for how that value reaches the machine.

### raise

```p
raise eAddOperation;                    // terminates the current function immediately
raise eAddOperation, (id = 1,);
```

Control jumps out of the function and the machine handles the event at once. `raise halt;` terminates the
machine — a bare `halt;` is wrong.

### goto

```p
goto WaitForRequests;
goto WaitForRequests, lastReqId;        // payload becomes the target state's entry parameter
```

Must appear inside a function body. On `goto` the machine exits the current state, abandoning the rest of
the current function.

### announce

```p
announce eStateUpdate, (node = source, state = ACTIVE);
```

Publishes synchronously to every spec monitor whose `observes` list contains the event, and to monitors
only. It cannot change system behavior, which is what makes it safe for instrumenting a model.

### receive

A blocking statement, used inside a function, not a function call:

```p
fun AcquireLock(lock: machine) {
    send lock, eAcquireLock;
    receive {
        case eLockGranted: (result: tResponse) { }
    }
    print "Lock acquired";
}

fun WaitForTime(timer: Timer, time: int) {
    var success: bool;
    send timer, eStartTimer, time;
    receive {
        case eTimeOut: { success = true; }
        case eStartTimerFailed: { success = false; }
    }
}
```

While blocked, every event not named in a `case` is deferred automatically.

## Constants

P has no `const`. Use a zero-argument function:

```p
fun MAX_RETRIES(): int { return 3; }
fun FAR_FUTURE(): int { return 1000000; }
```

## Nondeterminism

`choose()` gives the model checker a decision point to explore, which is how you model data
nondeterminism instead of hard-coding one scenario.

```p
choose()                      // random bool; `$` is shorthand for this
choose(n)                     // random int in [0, n) -- note: excludes n
choose(sq)                    // random element of a seq or set
choose(mp)                    // random KEY of a map
```

At most 10,000 choices: `choose(20000)`, or a choose over a collection of more than 10,000 elements, is a
runtime error. So is a choose over an empty collection.

Idiomatic uses, from the tutorials:

```p
SetupClientServerSystem(choose(3) + 2);      // 2..4 clients, so the checker explores all three
bankBalance[i] = choose(100) + 10;           // random opening balance, at least 10
send choose(participants), eReadTransReq, rTrans;   // pick an arbitrary participant
```

Each `choose` multiplies the state space, so prefer the smallest range that still covers the behavior you
care about.
