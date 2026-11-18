# PChecker failure remediation

Per-category procedure, from PeasyAI's `fixing.py::_get_manual_fix_guidance` and
`instructions/semantic-fix-sets/hot-state/analysis_prompt.txt`.

Work categories in this order when a trace shows more than one — each is more likely to be the root cause
of the others than the reverse:

**unhandled event → null target → assertion failure → deadlock/liveness**

## Unhandled event

`<ErrorLog> ... received event ... that cannot be handled`

A state had no `on`, no `defer` and no `ignore` for an event that arrived. First decide **which kind of bug
it is**, because the fixes are opposites.

### Protocol-logic bug

The event legitimately belongs to the protocol and the receiving state should cope with it.

1. Trace back to the sender — find where the event is sent.
2. Decide whether the receiving state should process, postpone or drop it.
3. Add the handler in the receiving state.
4. Check whether other machines also lack a handler for the same event.
5. Update specs or tests if the expected behavior changed.

```p
state Serving {
  // A: it is genuinely irrelevant here
  ignore eLateReply;

  // B: not yet — handle it in a later state
  defer eLateReply;

  // C: handle it
  on eLateReply do HandleLateReply;
}
```

Choose deliberately. `ignore` on an event that mattered converts a crash into a silent wrong answer, which
is worse — the checker stops complaining and the model stops being true.

### Test-driver bug

The driver is sending a *protocol* event to set something up. The fix is a dedicated setup event, not a
handler for the protocol event.

1. Work out why the driver is sending a protocol event at all.
2. Add a dedicated setup event to `Enums_Types_Events.p`.
3. Handle it in the receiving machine's `Init` state.
4. Change the driver to send the setup event.
5. `ignore` the protocol event in machines that may still receive it early.
6. Confirm the safety specs can still observe the events they monitor.

```p
// Enums_Types_Events.p
type tSetupCoordinator = (components: seq[machine]);
event eSetupCoordinatorComponents: tSetupCoordinator;

// Coordinator.p
start state Init {
  entry InitEntry;
  on eSetupCoordinatorComponents do (p: tSetupCoordinator) { components = p.components; }
  ignore ePrepare;
}

// TestDriver.p
send coordinator, eSetupCoordinatorComponents, (components = allComponents,);
```

Step 6 is the one that gets skipped. Rerouting an event around a monitor's `observes` list silently
disables that monitor.

## Null target

`... sent to a null machine`, or an unhandled null exception.

A machine reference was used before it was assigned — almost always initialization order.

1. Find the variable in the trace and the state it was used from.
2. Find where it should have been assigned: a constructor payload (Pattern A) or a config event
   (Pattern B).
3. If Pattern A, check the `new` call actually passes it, and that the field name matches the type.
4. If Pattern B, check the config event is sent *and* that the machine defers real work until it arrives.
5. Check for a dependency cycle — see `p-project/references/wiring-review.md`.

`default(machine)` is `null`, so a machine field that was never configured reads as null rather than
failing at creation. An empty `default(set[machine])` passed as config produces the same class of bug one
step later.

## Assertion failure

`<ErrorLog> Assertion Failed: file:line:col <message>`

The interesting case: a real property was violated, so the model is telling you something.

1. Read the assertion at the named source location and the message text.
2. State what was expected versus what the trace shows.
3. Read the trace **backwards** from `<ErrorLog>` to find where the invariant first broke — not where it
   was detected.
4. Decide which is wrong: the system logic, or the property.

That last step is the real work. An assertion failure is not automatically a bug in the system. It can
mean:

- the system is wrong — fix the logic;
- the property is wrong or overstated — fix the spec, and say so;
- the property is right and the failure is **intended** for this test case.

The third is live in this repo: `tcFleetNaive` and `tcFleetSanctionFairness` are *expected* to produce
counterexamples, and the comment above each says so. Do not "fix" an intended counterexample. Check
`PTst/TestScript.p` before changing anything.

Never weaken an assertion to make a test pass. If a property is genuinely too strong, narrow it
deliberately and record why.

## Deadlock

`Deadlock detected`. Every machine is blocked and nothing can proceed.

1. Check which machines are waiting, and in which states.
2. Look for a cycle in event handling — A waits on B, B waits on A.
3. Confirm the events each machine is waiting for are actually sent by someone.
4. Consider whether a timeout belongs in the model.

A blocking `receive` is a common source: if the awaited event never arrives, the machine waits forever.

## Liveness / hot state

A monitor was left in a `hot` state when execution ended: an obligation was created and never discharged.

Procedure:

1. **Locate the hot state** and identify which machine or monitor owns it.
2. **Trace backwards**: what sequence of events should lead *out* of the hot state?
3. **Check event generation**: is some machine actually sending the required exit event?
4. **Verify delivery**: can the event reach its target — is the addressing right?
5. **Examine transitions**: is a guard or condition blocking an otherwise valid transition?
6. **Look for crashed machines**: did one terminate on an unhandled event, taking its future sends with
   it? This is why unhandled events get fixed first.
7. **Check initialization order**: was every machine configured with all its dependencies?
8. **Consider timing**: could a late-arriving message be the cause?

Then say which machine is stuck, what it was waiting for, and what is missing — citing lines from the
trace.

Bounded runs matter here. A liveness property can only fail by the *end* of an execution, so a run that
ends early reports violations that a longer run would not. This is what
`Projects/ProjectRobot2026/Common/Clock.p`'s final `FAR_FUTURE()` tick is for: it closes every open
obligation so liveness checks stay meaningful in a bounded run.

Related: the project's runtime specs (`RuntimeSpecs.p`) restate two liveness monitors as
*bounded-response safety* properties, because a finite log cannot prove "eventually". R1 and R2 are
deliberately **not** wired into the checker tests, since `eTick` ordering there would raise false alarms.
Do not add them.

## Vacuous passes

A test that passes because nothing happened proves nothing. Treat as suspect:

- `Explored N schedules` with `Explored 1 timeline` — the checker kept walking one path.
- min, avg and max scheduling points all equal — only one behavior exists.
- A very low max depth relative to the protocol's length.
- A monitor that never left its start state (visible in the trace).

Check the monitor list at the top of the trace: a monitor absent from it was never attached to this test.

## After a fix

In this order:

1. `p compile`.
2. Replay the original counterexample: `check -tc <tc> --replay <seed>`. This confirms you fixed *this*
   bug rather than perturbing the schedule space.
3. Re-check at a low count (`-s 50`) for a fast signal.
4. Re-check at the full count.
5. Re-run the *other* test cases. A fix that satisfies one monitor often breaks another.

If any step regresses, revert and reconsider. PeasyAI's own fix loop backs up every file it touches and
reverts the whole set on failure; do the same, and do not leave a half-applied fix in the tree.
