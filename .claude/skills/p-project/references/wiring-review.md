# Wiring and spec review

From PeasyAI's `review_test_wiring.txt` and `review_spec_correctness.txt` — its LLM review stages, which
exist because these defects **compile cleanly and fail at check time**. No static analysis catches them.

Review a test driver against the machines' constructor signatures, and a spec against the design doc's
properties. You need three things in view: the driver, every machine's start-state entry signature, and
`Enums_Types_Events.p`.

---

# Part 1 — Test driver wiring

## Check 1: dependency order

Every `new Machine(config)` must happen **after** the machines referenced in `config` exist.

```p
// BAD — nodeSet is still empty when the detector is created
fd = new FailureDetector((nodes = nodeSet,));
node1 = new Node((failureDetector = fd,));
nodeSet += (node1);

// GOOD
node1 = new Node((failureDetector = fd,));
nodeSet += (node1);
fd = new FailureDetector((nodes = nodeSet,));
```

This fails silently. The collection is empty rather than absent, so the machine starts and does nothing —
surfacing much later as a liveness violation or a deadlock, far from the cause.

## Check 2: circular dependencies

If A's constructor needs B and B's constructor needs A, no ordering satisfies both. One side must use
the init-event pattern.

```p
// BAD — unsatisfiable; fd ends up with an empty node set
fd    = new FailureDetector((nodes = nodeSet,));
node1 = new Node((failureDetector = fd,));

// GOOD — break the cycle with an init event
fd    = new FailureDetector();                      // starts unconfigured
node1 = new Node((failureDetector = fd,));
nodeSet += (node1);
send fd, eFDInit, (nodes = nodeSet,);               // configure after the fact
```

Or break it on the other side, if that machine can start unconfigured:

```p
node1 = new Node();
nodeSet += (node1);
fd = new FailureDetector((nodes = nodeSet,));
send node1, eNodeInit, (failureDetector = fd,);
```

### Choosing a side

Break the cycle on the machine whose constructor is **simpler** — fewer fields, or fields that are easier
to supply later.

Then follow through completely. Breaking a cycle is a three-file change:

1. Remove the field from that machine's config type in `Enums_Types_Events.p`, and add a typed init
   event.
2. Update the machine: its start state waits for the init event and **defers** the events it cannot yet
   handle. Without that `defer`, work arriving before configuration is an unhandled event — the same bug
   relocated.
3. Update the driver to send the init event.

If the machine already uses Pattern B, use the handler it has rather than adding another.

## Check 3: no empty collections as config

```p
// BAD
fdConfig = (nodes = default(set[machine]),);
fd = new FailureDetector(fdConfig);

// GOOD
nodeSet += (node1);
nodeSet += (node2);
fd = new FailureDetector((nodes = nodeSet,));
```

`default(set[machine])` is empty, not null, so nothing complains. A detector monitoring nothing reports
nothing and the test passes vacuously.

## Check 4: named tuple construction

Every `new Machine(...)` and `send ..., eEvent, ...` must match the declared type exactly — right field
names, all fields, trailing comma on a single-field value. Check against `Enums_Types_Events.p`, not
against memory of what it says.

## Check 5: timer targets

A `Timer` created with the test driver as its client sends `eTimeOut` to the driver, not to the machine
waiting on it. Pass the machine that handles the timeout.

```p
// BAD, inside a driver
t = new Timer(this);
// GOOD
t = new Timer(nodeThatWaitsOnIt);
```

---

# Part 2 — Spec correctness

## Check 1: `observes` completeness

Reason **from the property to the events that carry the information it needs**. Not from the events that
seem related.

Worked example — *"if a node crashes, it must eventually be suspected"*:

- `eCrash` — to know a crash happened
- `eNodeSuspected` — to know a suspicion happened
- `eHeartbeat` — to know a crashed node stopped sending

```p
spec ReliableDetection observes eNodeSuspected { ... }                      // BAD: incomplete
spec ReliableDetection observes eCrash, eHeartbeat, eNodeSuspected { ... }  // GOOD
```

An incomplete `observes` list produces a monitor that compiles, runs, and cannot see the violation.

## Check 2: event-to-machine tracking

**A monitor observes events globally.** `on eCrash do ...` fires for *every* `eCrash` in the system, with
no notion of which machine it was "for".

The consequence: **a payload-less event cannot identify its target.** If `eCrash` is sent to a specific
node but carries no payload, the monitor sees that *a* crash happened and cannot tell whose. Either give
the event a payload, or infer the identity from other events that do carry one — e.g. the absence of
heartbeats from a specific node.

When an event does have a payload, the handler must take it and use it:

```p
// BAD — counts events, tracks nothing
on eNodeSuspected do { suspectedCount = suspectedCount + 1; }

// GOOD — tracks which machine
on eNodeSuspected do (payload: tNodeSuspectedPayload) {
  suspectedNodes += (payload.suspectedNode);
}
```

A counter is almost always a sign the property is not really being checked. Most interesting properties
are about a *specific* request or machine, not about totals.

## Check 3: assertion logic matches the property

Read the property, then read the assertion, and check they are the same claim.

```p
// Property: "if a node crashes, it must eventually be suspected"

// BAD — true, but about something else entirely
assert !(node in heartbeatAfterSuspicion), "Node sent heartbeat after suspicion";

// GOOD — tracks crashed nodes against suspected nodes
on eNodeSuspected do (payload: tNodeSuspectedPayload) {
  if (payload.suspectedNode in crashedNodes) { detectedCrashes += (payload.suspectedNode); }
}
```

An assertion that is locally true but unrelated to the property is the worst outcome available: a green
test that proves nothing, with a spec file that looks like diligence.

## Check 4: forbidden keywords

No `this`, `new`, `send`, `announce`, `receive`, `$`, `$$` or `pop` in a spec body. Per-machine state goes
in `map[machine, T]` keyed from a payload.

## Check 5: exact payload types

Handler parameter types must match `Enums_Types_Events.p` exactly.

---

## Review checklist

Wiring:

- [ ] No `new` before the machines its config references exist.
- [ ] No unsatisfiable cycle; any cycle broken with a typed init event.
- [ ] A Pattern B machine defers work until configured.
- [ ] No empty or `default()` collection passed as config.
- [ ] Every `new`/`send` payload matches its declared type exactly.
- [ ] Timers wired to the machine that handles the timeout.

Specs:

- [ ] `observes` covers everything the property needs to know.
- [ ] Handlers use payloads to identify specific machines, not just count.
- [ ] Each `assert` expresses the property from the design doc.
- [ ] No forbidden keywords.
- [ ] Payload types match the declarations.
- [ ] Each monitor is listed in the tests that should enforce it.
