# P spec monitors

Condensed from PeasyAI's `p_spec_monitors_guide.txt` and `generate_spec_files.txt`. Monitors are where a
model stops being a simulation and starts being a specification, so this is the part worth getting right.

## What a monitor is

```p
spec ReqIdsAreMonotonicallyIncreasing observes eRequest {
  var previousId: int;

  start state Init {
    on eRequest do CheckMonotonic;
  }

  fun CheckMonotonic(req: tRequest) {
    assert req.rId > previousId,
      format("Request Ids not monotonically increasing, got {0}, previously seen {1}",
             req.rId, previousId);
    previousId = req.rId;
  }
}
```

A monitor observes events and asserts a global property over what it sees. It is **synchronously
composed** with the system: at every `send` or `announce` of an observed event, every monitor observing
that event runs at that point, before the event is delivered. A monitor is a single global instance
created at startup — there is no dynamic creation.

## Rules

1. **No side effects.** `send`, `announce`, `new`, `receive`, `pop`, `$` and `$$` are all forbidden. A
   monitor that could act could change the behavior it is meant to judge.
2. **No `this`.** There is one instance, so there is no identity to refer to. To track per-machine state,
   use `map[machine, T]` keyed on a machine taken from an event payload.
3. **`entry` functions take no parameters.** Handlers do: `on eX do (p: tX) { ... }`.
4. **Every monitor needs at least one `assert`.** A monitor with no assertion and no `hot` state checks
   nothing and will pass vacuously.
5. **One property per `spec`.** Two properties in one monitor make a counterexample ambiguous.
6. **No empty or placeholder functions.** If you declare it, implement it.
7. **It can only observe events that exist.** An `observes` list naming an undeclared event does not
   compile.
8. **An event handled in the body must be in the `observes` list.** Handling an unobserved event does not
   compile either — this is a compile error, not a silent no-op.

## Safety vs liveness

**Safety** — something bad never happens. Plain states and `assert`:

```p
spec RegimentationSafety observes eZoneEntered, eZoneExited {
  var occupancy: map[int, int];
  var capacity: int;

  start state Monitoring {
    on eZoneEntered do (p: tZoneEvent) {
      if (!(p.zone in occupancy)) { occupancy[p.zone] = 0; }
      occupancy[p.zone] = occupancy[p.zone] + 1;
      assert occupancy[p.zone] <= capacity,
        format("zone {0} over capacity: {1}", p.zone, occupancy[p.zone]);
    }
  }
}
```

**Liveness** — something good eventually happens. Mark the intermediate state `hot`. The system satisfies
the property if execution does not *end* in a hot state; an execution that never leaves one is a liveness
violation.

```p
spec GuaranteedProgress observes eRequest, eResponse {
  var pendingReqs: set[int];

  start state NoPendingRequests {
    on eRequest goto PendingReqs with AddPendingRequest;
  }

  hot state PendingReqs {
    on eResponse do AfterResponse;
    on eRequest goto PendingReqs with AddPendingRequest;
  }

  fun AddPendingRequest(req: tRequest) { pendingReqs += (req.rId); }

  fun AfterResponse(resp: tResponse) {
    assert resp.rId in pendingReqs,
      format("unexpected rId {0}, expected one of {1}", resp.rId, pendingReqs);
    if (resp.status == SUCCESS) {
      pendingReqs -= (resp.rId);
      if (sizeof(pendingReqs) == 0) { goto NoPendingRequests; }
    }
  }
}
```

The pattern: start in a cold (unmarked) state, enter `hot` when an obligation is created, return to cold
only when every obligation is discharged. `cold` can be written explicitly for clarity.

## Getting `observes` right

This is the most common semantic defect in a generated monitor, and no regex catches it. Reason **from the
property to the events that carry the information the property needs**, not from the events that happen to
be nearby.

A monitor sees events globally, with no notion of which machine it is "for". So a payload-less event
cannot identify its own target: if `eCrash` carries nothing, the monitor cannot tell *which* node crashed,
and must infer it from other events that do carry an identity. Either give the event a payload or track
identity through a different event.

Checklist before accepting a monitor:

- Does `observes` include every event needed to decide the property — not just the obvious one?
- Does each handler use its payload to track the *specific* machine or request, rather than only counting?
- Does the `assert` condition actually express the property from the design doc, or just something
  locally true?
- Do the handler parameter types match the declarations in `Enums_Types_Events.p` exactly?

## Wiring a monitor into a test

A monitor only runs in tests that name it. See [tests-modules.md](tests-modules.md). A monitor not listed
in a test's `assert ... in { ... }` is dead code for that test, which is a passing test that checks
nothing.

## Feeding a monitor

`announce` publishes to monitors only and cannot affect system behavior, which makes it the safe way to
give a monitor information the protocol itself does not send:

```p
announce eMonitorConfig, (capacity = zoneCapacity,);
```

Monitors also observe ordinary `send` events automatically, so most monitors need no instrumentation at
all.
