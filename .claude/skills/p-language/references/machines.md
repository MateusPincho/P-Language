# P state machines

Condensed from PeasyAI's `p_machines_guide.txt` and `generate_machine_structure.txt`, with idioms taken
from this repo's `Projects/ProjectRobot2026/Common/`.

## Semantics

A machine is an actor. It owns private variables, has an unbounded FIFO input buffer, and runs one event
at a time to completion. `send` is asynchronous and never blocks the sender. Nothing outside a machine can
read its variables or call its functions, so all interaction is by event. When a machine has no event it
can handle, it blocks until one arrives.

## Shape

```p
machine Server {
  var clients: seq[machine];              // all vars at the top of the machine
  var requestCount: int;

  start state Init {
    entry (cfg: tServerConfig) {          // or: entry InitEntry;
      clients = cfg.clients;
      requestCount = 0;
      goto Serving;
    }
  }

  state Serving {
    entry { }
    exit { }                              // exit functions take NO parameters
    on eRequest do HandleRequest;          // run a handler, stay in this state
    on eShutdown goto Stopping;            // transition
    on eConfigChanged goto Serving with Reconfigure;   // transition AND run a function
    defer eLateReply;                      // queue for a later state
    ignore eHeartbeat;                     // silently drop
  }

  state Stopping {
    entry { raise halt; }                  // terminate this machine
  }

  fun HandleRequest(req: tRequest) {
    var reply: tResponse;                  // vars at the top of the function body
    requestCount = requestCount + 1;
    reply = (client = req.client, status = OK, rId = req.rId);
    send req.client, eResponse, reply;
  }
}
```

Exactly one state is `start`. Every machine needs one or the project will not compile.

## Event handling completeness

**Every state must handle, `defer`, or `ignore` every event that can reach it** — including events still
sitting in the queue from an earlier state. An event with no handler, no `defer` and no `ignore` is an
unhandled-event failure that PChecker will find, and it is the most common checker bug in generated code.

When writing a state, go through the events the design says can arrive and choose deliberately:

- `on eX do Handler;` — process it here
- `defer eX;` — not yet; keep it queued for a later state
- `ignore eX;` — it is genuinely irrelevant here, drop it

`ignore` takes a list: `ignore eTick, eHeartbeat;`.

## Machine configuration: pick one pattern

How a machine learns about its dependencies decides how the test driver wires the system. Choose one
pattern per machine and stay consistent.

### Pattern A — constructor payload

Preferred when every dependency exists at creation time.

```p
machine ExampleServer {
  var workers: seq[machine];
  var serverId: int;

  start state Init {
    entry InitEntry;
    on eRequest goto Serving;
  }

  fun InitEntry(config: (workers: seq[machine], id: int)) {
    workers = config.workers;
    serverId = config.id;
  }
}
```

Created as `new ExampleServer((workers = workerList, id = 1));`.

### Pattern B — initialization event

For when configuration cannot exist at creation time, which in practice means **breaking a circular
dependency**: A needs a reference to B and B needs a reference to A, so one of them must be created first
and told about the other afterwards.

```p
machine ExampleWorker {
  var coordinator: machine;

  start state WaitForConfig {
    on eWorkerConfig goto Ready with Configure;
    defer eTask;                      // defer real work until configured
  }

  state Ready {
    on eTask do HandleTask;
  }

  fun Configure(config: tWorkerConfig) {
    coordinator = config.coordinator;
  }
}
```

Created and configured as:

```p
worker1 = new ExampleWorker();
send worker1, eWorkerConfig, (coordinator = coord,);
```

The `defer` in `WaitForConfig` is not optional. Without it, a task arriving before the config event is an
unhandled event.

### Rules

- One pattern per machine.
- A Pattern B config event needs a real typed payload declared in `Enums_Types_Events.p`. Do not invent
  bare `eStart`/`eInit` events carrying nothing.
- A machine with no external dependencies takes no entry parameter at all.
- A named `entry` function takes **at most one** parameter, so group configuration into one named tuple.
- When only one side of a cycle needs breaking, apply Pattern B to the machine with the simpler config.

## Machine references and types

A machine name doubles as a type, so a variable can be typed `Server` rather than `machine`:

```p
var server: Server;
var nodes: seq[machine];
```

`machine` accepts any machine. Use the specific type when the target is fixed — it lets the compiler catch
a send to the wrong kind of machine. `null` is the default for both.

## Interaction patterns

```p
// Broadcast
fun Broadcast(t: int) {
  var i: int;
  i = 0;
  while (i < sizeof(subscribers)) {
    send subscribers[i], eTick, t;
    i = i + 1;
  }
}

// Self-scheduling: drive a loop without a timer
state Ticking {
  entry {
    if (now < maxTicks) { now = now + 1; Broadcast(now); send this, eContinue; }
    else { goto Stopped; }
  }
  on eContinue goto Ticking;
}

state Stopped { ignore eContinue; }
```

`send this, eContinue;` is how a machine yields and comes back, letting other machines interleave. A tight
`while` loop does not.

## House idioms in this repo

From `Projects/ProjectRobot2026/Common/`:

- A doc comment above every machine and spec stating the modeling choice **and what is not modeled**.
- Configuration arrives as one named tuple to the start state's `entry`.
- Constants are zero-argument functions, since P has no `const`:
  `fun FAR_FUTURE(): int { return 1000000; }`.
- `announce eMonitorConfig, capacity;` to seed spec monitors from the system machine.
- One system-assembly machine (e.g. `FleetSystem`) whose only job is to `new` everything in dependency
  order and seed the initial work. Test driver machines then just `new FleetSystem(cfg);`.
- 2-space indent.
