# Warehouse Fleet: Regulation of a Single-Lane Corridor

Source: `docs/Multi-Robot Fleet in a Warehouse update.pdf` (15 slides). This document restates that
specification as a P design document (the six-section contract in
`.claude/skills/p-project/references/design-doc-template.md`) and records how each norm maps to the P
model in `WarehouseFleet/`.

Two kinds of statement appear below, and they are kept apart on purpose:

- **From the PDF**: the system, the norms N1–N8, the machine and event tables, and properties 1–4.
- **Modeling decisions (ours)**: every choice the PDF leaves open, and every event or property we add.
  They are collected in [§7](#7-modeling-decisions-ours-not-in-the-pdf) and marked *(ours)* where they
  appear.

The model's purpose is to check the regulation layer: does the combination of the distributed zone
controllers and the centralized Fleet Manager and Adaptation Coordinator enforce the norms?
Whether it does is a question for `p check`, and the answers are recorded, with schedule counts, in
`README.md` → *Status*. Nothing here is a verification result.

---

## 1. Introduction

A warehouse has two stations, **A** and **B**, joined by a **single-lane corridor** with three critical
zones (**Zone 0, Zone 1, Zone 2**). Each zone has a **Side Bay** (Bay 0, 1, 2) next to it and a
**Zone Controller** that admits or denies robots according to the version of the norm set it currently
holds. Two autonomous robots start one per station: **R1 at Station A** and **R2 at Station B**.

The **Fleet Manager** (`ObligationManager`) assigns each robot a delivery task. A task has a package
priority (1–10), a deadline (1–15 ticks), an origin and a destination station. Priority belongs to the
package, not the robot. Moving in opposite directions, the robots meet head-on in the corridor; the
controllers resolve the conflict by priority, and the loser retreats to a side bay. A robot that misses
its deadline is sanctioned.

Occasionally a **Human Picker** needs Zone 1. The **Adaptation Coordinator** then switches the norm set
from **V1** (normal operation) to **V2** (human safety mode), which locks and evacuates Zone 1, and
restores V1 when the human leaves.

The architecture has two layers (slide 2): the *physical system* (robots, zone controllers, human
picker; distributed coordination) and the *regulation layer* (Adaptation Coordinator and Fleet Manager;
central coordination), the latter being what is modeled in P.

**Assumptions:**

1. Message delivery is reliable and, between any pair of machines, in order (P's semantics). No
   crashes, no message loss, no Byzantine behavior.
2. P is untimed. Time is a logical `Clock` whose `eTick` is consumed only by the `ObligationManager`
   (deadlines and cooldowns). Robots move asynchronously, so the checker can place a deadline expiry at
   any point of a trip *(ours; user decision)*.
3. Each zone holds at most one robot. Side bays and stations have no capacity limit.
4. Exactly two robots, three zones, one human picker, one task per robot in a bounded run *(ours; user
   decision)*.
5. A robot always holds its current zone while requesting the next one; it never stands between zones.

## 2. Norms (from the PDF, verbatim) and how the model implements them

### Norm set V1: normal operation

| Norm | Text (slide 8) | Implemented by |
|---|---|---|
| **N1 Mutual Exclusion** | Each zone admits at most one robot at a time. A request for an occupied zone is denied and the requester waits. | `ZoneController.OnRequest`: grant only if free; otherwise `eDeny` and queue the request in `waiters`. The robot waits for a later `eGrant`. |
| **N2 Priority** | When two robots request the same zone, the controller admits the one with the higher package priority. On a tie, the robot with fewer infractions wins; if still tied, R1 wins. A robot returning empty has priority 0. | `Wins(a, b)` in `ZoneController.p` (priority ↓, violations ↑, robot id ↑). Used for both preemption and choosing among queued waiters. A returning robot sends `priority = 0`. |
| **N3 Preemption** | A robot occupying a zone must retreat to the adjacent Side Bay when a robot that wins over it under N2 requests that zone. Retreat is not a sanction: the robot keeps its delivery and may return when the zone is free. | Controller sends `ePreempt`; `Robot` leaves the zone, releases it, withdraws any queued next-zone request, waits in the bay (`InBay`) and re-requests the same zone. No event to the Fleet Manager. |
| **N4 Deadline & Sanction** | A robot with an active delivery that exceeds its tick deadline abandons it and goes to the adjacent Side Bay. The Fleet Manager increments its infraction counter and applies a fixed cooldown (COOLDOWN ticks) before the robot returns empty to a station for a new task. | `ObligationManager` decrements the deadline each `eTick`; at 0 it self-sends `eDeadlineExpired`, increments infractions and sends `eSanction`. The robot abandons (`Abandon`), waits for `eCooldownOver`, then returns to its origin with priority 0. |

### Norm set V2: human safety mode (V2 = V1 + N5–N7)

| Norm | Text (slide 11) | Implemented by |
|---|---|---|
| **N5 Zone 1 Lockout** | From the switch to V2 until HumanExit, Zone Controller 1 denies all entry requests into Zone 1. Denied robots wait. | `ZoneController.Locked()` is true for zone 1 under V2: every request is denied and queued, none is granted. |
| **N6 Mandatory Evacuation** | A robot in Zone 1 when HumanRequest is triggered is preempted and retreats to Bay 1, regardless of priority. The human enters only after Zone 1 is empty. | On `eNormChange(V2)`, controller 1 sends `ePreempt` to its occupant without consulting N2, and acks the coordinator only once the zone is empty. The coordinator lets the human in only after every controller has acked. |
| **N7 Deadlines Keep Running** | Deadline counters are not paused in V2. A robot that exceeds its deadline while the human is active is sanctioned as in N4. | The `ObligationManager` has no notion of the norm version; ticks are processed identically under V1 and V2. |
| **N8 Restoration** (transition rule) | On HumanExit, the Adaptation Coordinator restores V1. | `AdaptationCoordinator.HumanActive` → on `eHumanExit` broadcast `eNormChange(V1)`, collect acks, return to `NormalV1`. |

Slide 13 states that a sanction caused by waiting for a locked Zone 1 (N5 + N7) is **a conflict between
obligation and adaptation, not a design flaw**. The model therefore does not treat such a sanction as an
error; property 4 only asks that it be *reachable*.

## 3. Components

The PDF's machine table (slide 14) lists six machines. All six are source components (`PSrc/`). The
test driver is the only test component.

### Source components

#### 1. Robot (×2)

- **Role:** Travels the corridor carrying one package from its origin to its destination station.
- **States:** `Init`, `AtStation`, `Traveling`, `InBay`, `Arrived`, `CoolingDown`, `Done`.
- **Local state:**
  - `id`: 1 for R1, 2 for R2 (R1 wins the final N2 tiebreak).
  - `controllers`: the three zone controllers, indexed by zone.
  - `om`: the Fleet Manager, learned from the task assignment.
  - `violations`: infraction count as last reported by the Fleet Manager (N2 tiebreak).
  - `task`, `priority`: the current task and the priority it presents (the package's, or 0 when
    returning empty).
  - `route`, `pos`: the zones in travel order, and the index of the zone held (or of the bay's zone).
  - `curZone`/`curReqId`: the zone held and the request that won it. `pendingZone`/`pendingReqId`: the
    outstanding request. `bay`: the side bay the robot is in, or -1.
  - `returning`: true on the empty return trip after a sanction.
- **Initialization:** Created with its id, the controllers and its initial infraction count. Waits in
  `AtStation` for `eTaskAssigned`, whose payload also carries the Fleet Manager's reference.
- **Behavior:**
  - Requests `route[pos+1]`, keeping its current zone. On `eGrant` it leaves the current zone (announces
    `eZoneLeft`, sends `eRelease`) and enters the next (announces `eZoneEntered`). `eDeny` means wait.
  - Past the last zone it exits to the destination station and sends `eArrived`; the delivery counts
    only when the Fleet Manager answers `eDeliveryConfirmed`.
  - On `ePreempt` for the zone it holds (N3/N6) it retreats to that zone's bay, withdraws any queued
    request with `eCancelRequest`, and from `InBay` re-requests the same zone.
  - On `eSanction` (N4/N7) it abandons: leaves and releases any zone, withdraws any request, and waits in
    the adjacent bay (or at the station it is standing at) for `eCooldownOver`. From a bay it then
    returns empty, priority 0, to its origin station and sends `eReturned`.
- **Event handling notes:**
  - Every request carries a fresh `reqId`; a grant or preemption is acted on only if it matches the
    current request or holding. Stale ones are ignored (their zone was already freed by the matching
    `eRelease`/`eCancelRequest`).
  - `Arrived`, `CoolingDown`, `Done`: ignore `eGrant`, `eDeny`, `ePreempt` (stale only).

#### 2. ZoneController (×3)

- **Role:** Grants or denies entry to one zone according to its installed norm version (N1, N2, N3, N5,
  N6).
- **States:** `Init`, `Serving` (all logic is data-driven by `version`).
- **Local state:** `zone`; `version` (V1/V2); `occupied` and `occ` (the occupant's request);
  `waiters` (robot id → queued request); `preempting` (an `ePreempt` is outstanding);
  `awaitingClear` (V2 ack owed once the zone empties); `coord`.
- **Initialization:** Created with its zone index; starts in V1.
- **Behavior:**
  - Request: if locked (V2 and zone 1) deny and queue (N5); if free grant (N1); otherwise deny and queue,
    and if the requester wins over the occupant under N2 and no preemption is outstanding, send
    `ePreempt` to the occupant (N3).
  - `eRelease` or `eCancelRequest` from the occupant frees the zone; then either ack a pending V2 switch
    (N6) or grant the N2-best waiter.
  - `eNormChange(V2)` at zone 1: evacuate the occupant regardless of priority (N6); ack only once empty.
    Any other zone, or V1: ack at once and, if free, grant the best waiter.

#### 3. ObligationManager (the Fleet Manager)

- **Role:** Assigns tasks, tracks deadlines and cooldowns per robot, applies sanctions (N4, N7).
- **States:** `Init`, `Supervising`, `AllDone`.
- **Local state:** per robot: `remaining` ticks, `active` (obligation open), `cooldownLeft`,
  `infractions`; `finished` robots; `cooldown`; `clock`.
- **Initialization:** Created with the robots, one task per robot, the COOLDOWN value and the initial
  infraction counts. Sends `eTaskAssigned` to each robot and creates the `Clock`.
- **Behavior:**
  - `eTick`: decrement every open deadline; on reaching 0 close the obligation and self-send
    `eDeadlineExpired`. Decrement running cooldowns; on reaching 0 send `eCooldownOver`. Ack the tick.
  - `eDeadlineExpired`: increment infractions, send `eSanction` (with the new count and COOLDOWN).
  - `eArrived`: if the obligation is still open, close it and send `eDeliveryConfirmed`; otherwise ignore
    (the sanction is already on its way).
  - When every robot has delivered or returned, stop the clock.

#### 4. AdaptationCoordinator

- **Role:** Switches the norm set V1 ⇄ V2 for the human picker (N5–N8).
- **States:** `Init`, `NormalV1`, `SwitchingToV2`, `HumanActive`, `RestoringV1`.
- **Local state:** `controllers`, `human`, `acks`, `naive` (bug-injection flag for one test).
- **Initialization:** Created with the three controllers and the `naive` flag.
- **Behavior:** `eHumanRequest` → broadcast `eNormChange(V2)` → after all three acks, send
  `eHumanAccessGranted`. `eHumanExit` → broadcast `eNormChange(V1)` → after all three acks, back to
  `NormalV1`. With `naive = true` the human is admitted right after the V2 broadcast, without waiting for
  the evacuation ack: a deliberately broken coordinator used to show that property 2 can fail.
- **Event handling notes:** `SwitchingToV2` defers `eHumanExit` (only reachable in naive mode).

#### 5. HumanPicker

- **Role:** Requests and releases Zone 1; behavior is nondeterministic.
- **States:** `Init`, `Idle`, `WaitingAccess`, `Working`, `Gone`.
- **Initialization:** Created with the coordinator and bounds on its arrival delay and its stay.
- **Behavior:** Waits a nondeterministic number of steps, sends `eHumanRequest`, on
  `eHumanAccessGranted` announces `eHumanEnter`, stays a nondeterministic number of steps, sends
  `eHumanExit`.

#### 6. Clock

- **Role:** Emits `eTick` to the Fleet Manager.
- **Initialization:** Created by the Fleet Manager with its reference.
- **Behavior:** Sends `eTick(n)`, waits for `eTickAck`, repeats, until `eStopClock`.

### Test components

#### 7. FleetScenario (+ one tiny driver per test case)

- **Role:** Builds the system from a scenario tuple: priorities, deadlines, initial infractions,
  COOLDOWN, whether the human is present, whether the coordinator is naive.
- **Initialization order:** controllers → coordinator → robots → Fleet Manager (which creates the clock)
  → human picker. No circular dependency: the robots learn the Fleet Manager from `eTaskAssigned`, and the
  controllers learn the coordinator from `eNormChange`.

## 4. Interactions

Events from the PDF's table (slide 15) keep their names. *(ours)* marks additions.

| Event | Payload | From → To | Norm | Effect |
|---|---|---|---|---|
| `eTaskAssigned` | task (id, robot, priority, deadline, origin, dest) + manager | ObligationManager → Robot | — | Robot starts the trip. |
| `eRequestZone` | robot, robot id, req id, zone, priority, violations | Robot → ZoneController | N1, N2 | Grant, or deny + queue (+ preempt if the requester wins). |
| `eGrant` / `eDeny` | zone, req id | ZoneController → Robot | N1, N5 | Enter / keep waiting. |
| `ePreempt` | zone, req id of the holding | ZoneController → Robot | N3, N6 | Retreat to that zone's bay. |
| `eRelease` *(ours)* | robot id, req id, zone | Robot → ZoneController | N1 | The robot has left the zone. |
| `eCancelRequest` *(ours)* | robot id, req id, zone | Robot → ZoneController | N3, N4 | Withdraw a queued request (or a grant not yet used). |
| `eDeadlineExpired` | robot id, task id | ObligationManager → itself | N4, N7 | Sanction follows. |
| `eSanction` | robot id, task id, cooldown, infractions | ObligationManager → Robot | N4 | Abandon the delivery. |
| `eCooldownOver` *(ours)* | robot id | ObligationManager → Robot | N4 | Start the empty return trip. |
| `eArrived` / `eDeliveryConfirmed` *(ours)* | robot id, task id | Robot ⇄ ObligationManager | N4 | Delivery handshake: the Fleet Manager alone decides delivered vs expired. |
| `eReturned` *(ours)* | robot id | Robot → ObligationManager | N4 | The robot is back at a station. |
| `eTick` / `eTickAck` *(ack ours)* | tick number / — | Clock ⇄ ObligationManager | N4, N7 | One logical time step. |
| `eStopClock` *(ours)* | — | ObligationManager → Clock | — | End of the bounded run. |
| `eHumanRequest` / `eHumanExit` | human ref / — | HumanPicker → AdaptationCoordinator | N5, N8 | Start / end of the V2 episode. |
| `eNormChange` | version (V1/V2), coordinator ref | AdaptationCoordinator → ZoneController | N5, N6, N8 | Install a norm version. |
| `eNormChangeAck` *(ours)* | zone, version | ZoneController → AdaptationCoordinator | N6 | Installed; for zone 1 under V2, also *empty*. |
| `eHumanAccessGranted` *(ours)* | — | AdaptationCoordinator → HumanPicker | N6 | Zone 1 is clear; the human may enter. |
| `eZoneEntered` / `eZoneLeft` | robot id, zone | announced by Robot | — | Monitor vocabulary (physical position). |
| `eHumanEnter` | — | announced by HumanPicker | — | Monitor vocabulary. |

## 5. Specifications

### From the PDF (slide 16)

1. **ZoneMutualExclusion** (safety). There are never two robots in the same zone: between a robot's
   `eZoneEntered(z)` and its `eZoneLeft(z)`, no other robot announces `eZoneEntered(z)`.
2. **NoRobotWithHuman** (safety). No robot is in Zone 1 while the human is inside: between `eHumanEnter`
   and `eHumanExit` no `eZoneEntered(1)` occurs, and when `eHumanEnter` occurs no robot is in Zone 1.
   The PDF lists `eHumanEnter, eHumanExit, eZoneEntered`; the monitor also observes `eZoneLeft`, which is
   needed to know Zone 1 is empty at the moment the human enters *(ours)*.
3. **SanctionOnlyAfterExpiry** (safety). Every `eSanction` for a task is preceded by an
   `eDeadlineExpired` for the same task, and there is at most one sanction per expiry.
4. **SanctionDuringV2** (cover). A sanction can occur while V2 is active (between `eNormChange(V2)` and
   `eNormChange(V1)`). P has no `cover` construct, so this is a *witness monitor* that asserts false
   when the situation is reached. It runs only in its own test, where a "bug" is the expected outcome:
   the trace is the proof of reachability.

### Additions *(ours)*

5. **NoDoubleOutcome** (safety). A task is never both confirmed delivered (`eDeliveryConfirmed`) and
   sanctioned (`eSanction`), and neither happens twice.
6. **EveryTaskResolved** (liveness). After `eTaskAssigned`, the task is eventually either confirmed or
   sanctioned.
7. **EveryRobotSettles** (liveness). Every robot that received a task eventually either has its delivery
   confirmed or returns to a station (`eReturned`). This catches a deadlock on the empty return trip,
   which property 6 does not cover.
8. **HumanEventuallyEnters** (liveness). After `eHumanRequest`, `eHumanEnter` eventually follows: the
   N6 evacuation cannot hang.

## 6. Test scenarios

One task per robot: R1 carries A → B, R2 carries B → A, so they meet head-on.
Each test's expected outcome is a **hypothesis until run**; results are in `README.md` → *Status*.

| Test | Setup | Monitors | Expected |
|---|---|---|---|
| `tcHeadOnV1` | R1 P=4, R2 P=8, deadlines 15, COOLDOWN 2, no human | 1, 3, 5, 6, 7 | all hold |
| `tcHumanAdaptation` | as above + human picker | 1, 2, 3, 5, 6, 7, 8 | all hold |
| `tcRandomTasks` | priority 1–10, deadline 1–15, infractions 0–1 (all `choose`), human | 1, 2, 3, 5, 6, 7, 8 | all hold |
| `tcNaiveAdaptation` | naive coordinator, human | 1, 2 | **intended counterexample** of property 2 |
| `tcCoverSanctionInV2` | deadlines 3–6, human arrives early and stays long | 4 | **intended witness** for property 4 |

## 7. Modeling decisions (ours, not in the PDF)

1. **Time.** Only the `ObligationManager` consumes `eTick`. Robot moves and the human's stay take no
   ticks; they interleave with ticks arbitrarily, so the checker explores an expiry at every possible
   point, including mid-retreat and while waiting for a locked Zone 1. The human's stay is a
   nondeterministic number of steps, which therefore spans a nondeterministic number of ticks.
2. **Return trip.** After the cooldown a sanctioned robot returns empty, priority 0, to the *origin*
   station of the cancelled task, re-entering the corridor at its bay's zone. A robot sanctioned while
   standing at a station (before entering, or after arriving too late) cools down there and is done.
3. **One task per robot.** A bounded run has exactly one task each.
4. **Delivery handshake.** Arrival (`eArrived`) and expiry race. The Fleet Manager is the single arbiter:
   whichever it processes first wins, and the robot learns the outcome by `eDeliveryConfirmed` or
   `eSanction`. An arrival processed after the tick that reached 0 is late.
5. **Request ids.** Each request carries a fresh id so a robot never acts on a stale grant or preemption
   left over from a request it withdrew while retreating or abandoning.
6. **Hold and request.** A robot keeps its zone while requesting the next; a denied robot does not
   re-send, the controller queues it and grants it later (by N2 if several wait).
7. **Who preempts.** A controller preempts on a *request* by a winner. It sends at most one preemption at
   a time. Waiters are re-ranked by N2 every time the zone frees.
8. **Evacuation ack.** "The human enters only after Zone 1 is empty" is implemented as a two-phase
   switch: the coordinator admits the human only after all three controllers ack V2, and controller 1
   acks only once empty. `tcNaiveAdaptation` removes the wait to show the check is not vacuous.
9. **Bays and stations** have unlimited capacity; a bay is entered and left without a controller.
