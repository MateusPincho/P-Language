# Experiments: the assignment's E0–E10 on the warehouse model

This file maps every experiment of the original assignment (E0–E10, written for the kit's
`ProjectRobot2026`) to the warehouse model in `WarehouseFleet/`. For each test that was run, it records:
- what the test checks;
- the exact command, seed and number of schedules;
- the prediction, written down **before** the first run;
- the observed result;
- for every counterexample, the reporting template of the kit's specification, section 7.8.

All results: P 3.1.0.0 in the `p-language:latest` container, run on 2026-11-23/24 from
`Projects/WarehouseFleet2026/WarehouseFleet/`. "0 bugs" means none in the stated number of schedules
under PChecker's default random strategy. It is evidence, not proof.

**Raw records:**
- `experiments/results.tsv` (test cases), `experiments/mutants.tsv` (E0 and calibration): one line per run.
- `experiments/logs/`: the checker's output for every run.
- `evidence/`: the saved counterexample traces, which can be replayed.
- `experiments/results-round*.tsv`, `mutants-before-*.tsv`: earlier rounds, kept on purpose (see §3).

---

## 1. How the experiments fit the model

The assignment defines most experiments as *changes to the model*. Here each change is a **switch**
in `tVariant` (`PSrc/Enums_Types_Events.p`) whose default, `BASELINE()`, is the final model. Each
experiment is a test case in `PTst/TestScript.p` that turns on one switch:

| Switch | Off (final model) | On (experiment) |
|---|---|---|
| `blockAll` (E4) | only Zone 1 locks under V2 | every controller locks and evacuates its zone until the coordinator commits V2 (`eNormCommit`); then zones 0 and 2 reopen |
| `parking` (E5) | robots retreat to side bays | no bays: a preempted robot stays put; a sanctioned robot keeps its zone and carries on empty |
| `remedy` (E7) | `NO_REMEDY` | `SUSPEND`: the coordinator tells the Fleet Manager when V2 starts (and waits for its ack) and ends; no deadline counts down meanwhile. `SUSPEND_EXCUSE`: also, an expiring deadline of a task that was open during V2 is excused instead of sanctioned |
| `oneDirection` (E6) | no direction rule | a `DirectionGuard` grants one travel direction at a time; robots wait at the station (or in a bay, before a return trip) for it |
| `abortable` (E9) | the switch to V2 always completes | the coordinator can time out while waiting for acks (nondeterministically), abort, restore V1 and refuse the human |

The controllers, robots, Fleet Manager and coordinator also **announce** what the new monitors need:
- every admission decision, with its cause (`eAccessDenied`, `eZoneGranted`, `ePreemptIssued`);
- abandonments (`eTaskAbandoned`);
- bay moves (`eBayEntered`, `eBayLeft`).

`announce` only reaches monitors, so it does not change what any machine does. All five switches off
reproduce the model as it was before the experiments. The three original passing tests still pass
(§4, E1), and the two original intended failures still fail the same way (E2, property 4).

### Monitors

| Monitor | Norm | Kind | Kit analogue | Added for |
|---|---|---|---|---|
| `ZoneMutualExclusion` | N1 | safety | S1 (capacity) | PDF property 1 |
| `NoRobotWithHuman` | N5, N6 | safety | S1 (person), S2, R3 | PDF property 2 |
| `SanctionOnlyAfterExpiry` | N4 | safety | — | PDF property 3 |
| `SanctionDuringV2` | N7 | cover (witness) | — | PDF property 4 |
| `NoDoubleOutcome` | N4 | safety | S3 | — |
| `EveryTaskResolved` | N4 | liveness | L1 | — |
| `EveryRobotSettles` | N4 (return trip) | liveness | — | — |
| `HumanEventuallyEnters` | N6 | liveness | L2 | — |
| `PriorityRespected` | N2 | safety | — | gap found in the first review |
| `EmptyRobotHasPriorityZero` | N2 | safety | — | gap |
| `OutrankedOccupantPreempted` | N3 | safety | — | gap |
| `DeadlinesKeepRunning` | N4, N7 | safety | (R1 as a design-time check) | gap |
| `V1EventuallyRestored` | N8 | liveness | (R2) | gap |
| `NoRegulationCausedSanction` | fairness | safety (candidate) | F1, refined | E3 |
| `NoTrafficCausedSanction` | fairness | safety (candidate) | F1, refined | E3 |
| `NoHeadOnConflict` | — | safety | — | E6 |
| `AdaptationTerminates` | — | liveness | L3 | E9 |
| `AbortNeverAdmits`, `AbortUnblocksControllers` | — | safety / liveness | E9 acceptance cases | E9 |
| `BayCapacityOne` | — | safety | — | E10 |

`PriorityRespected` and `OutrankedOccupantPreempted` check each controller decision against
`OutranksN2` in `Enums_Types_Events.p`. That is a second encoding of N2, written from the PDF and kept
separate from `ZoneController.Wins`, so a fault in the controller's rule cannot also change what the
monitor expects.

### Running a test

From `Projects/WarehouseFleet2026/WarehouseFleet/` inside the container (README §2):

```bash
p compile
p check -tc <test case> -s <schedules> --seed <seed>
```

**`-tc` matches by prefix.** `p check -tc tcE9Abort` would also run `tcE9AbortBreaksL2`. No test name in
`TestScript.p` is a prefix of another (this was not true at first; see §3). The scripts in
`experiments/` wrap the same commands:

```bash
# from Projects/WarehouseFleet2026/, on the host
experiments/run_tests.sh 10000 1 tcE4BlockAllParking            # any test cases
python3 -I experiments/run_mutants.py 10000 1                    # E0: every mutant
python3 -I experiments/run_mutants.py 100000 1,2,3,4,5,6,7,8,9,10 M08_N2   # calibration
experiments/run_scale.sh 10000 1 4                               # E8: 4 zones
```

---

## 2. Summary

| Exp. | Test case | `-s` | Prediction | Result | Matches |
|---|---|---|---|---|---|
| E0 | 15 mutants (`run_mutants.py`) | 10,000 | each kills its monitor | 15 / 15 killed | yes |
| E1 | `tcHeadOnV1` | 100,000 | hold | 0 bugs, 30 timelines | yes |
| E1 | `tcHumanAdaptation` | 100,000 | hold | 0 bugs, 540 timelines | yes |
| E1 | `tcRandomTasks` | 100,000 | hold | 0 bugs, 2,962 timelines | yes |
| E2 | `tcNaiveAdaptation` | 10,000 | fail `NoRobotWithHuman` | fails at schedule 6 | yes |
| P4 | `tcCoverSanctionInV2` | 10,000 | witness | witness at schedule 1 | yes |
| E3 | `tcE3FairnessRegulation` | 10,000 | fail | fails at schedule 1 | yes |
| E3 | `tcE3FairnessTraffic` | 10,000 | fail | fails at schedule 2 | yes |
| E3 | `tcE3TrafficNoHuman` | 10,000 | fail, traffic only | fails at schedule 1, no regulation delay | yes |
| E4 | `tcE4BlockAllParking` | 10,000 | hold | 0 bugs, 1,225 timelines | yes |
| E4 | `tcE4BlockAllNoParking` | 10,000 | fail `HumanEventuallyEnters` | fails at schedule 3 | yes |
| E5 | `tcE5NoParking` | 10,000 | fail `HumanEventuallyEnters` | fails at schedule 3 | yes |
| E6 | `tcE6HeadOnInBaseline` | 10,000 | fail `NoHeadOnConflict` | fails at schedule 1 | yes |
| E6 | `tcE6OneDirection` | 10,000 | hold | 0 bugs, 1,473 timelines | yes |
| E6 | `tcE6FairnessTraffic` | 10,000 | fail | **0 bugs**, 882 timelines | **no** |
| E6 | `tcE6FairnessRegulation` | 10,000 | fail | fails at schedule 1 | yes |
| E7 | `tcE7SuspendOnly` | 10,000 | fail | fails at schedule 4 | yes |
| E7 | `tcE7SuspendExcuseShort` | 10,000 | hold | 0 bugs, 440 timelines | yes |
| E7 | `tcE7SuspendExcuseRandom` | 10,000 | hold | 0 bugs, 1,061 timelines | yes |
| E7 | `tcE7Traffic` | 10,000 | fail | fails at schedule 3 | yes |
| E7 | `tcE7ReplacesN7` | 10,000 | fail `DeadlinesKeepRunning` | fails at schedule 1 | yes |
| E8 | `tcE8ThreeRobots`, 4 zones | 10,000 | hold, much slower | 0 bugs in all three sizes; only modestly slower | **partly** |
| E9 | `tcE9AbortSafety` | 10,000 | hold | 0 bugs, 3,438 timelines | yes |
| E9 | `tcE9AbortBreaksL2` | 10,000 | fail `HumanEventuallyEnters` | fails at schedule 3 | yes |
| E10 | `tcE10BayCapacity` | 10,000 | fail `BayCapacityOne` | fails at schedule 22 | yes |

"Fails at schedule k" is the number of schedules explored before the first bug, with seed 1. A failing
run stops there.

---

## 3. Findings about the experimental setup itself (internal validity)

Four problems surfaced while running the experiments. Three were in the monitors and one was in the
tooling; none was in the final model. Each is kept in an archived result file, because a monitor that
raises false alarms, or a test name that silently runs two tests, would otherwise invalidate results
(the "internal" class of threats, spec 7.6).

1. **Announcements arrive after the robot has moved on** (`results-round1-monitor-artifacts.tsv`). A
   controller sends `eDeny` and *then* announces the denial. A send is a scheduling point, so the robot
   could withdraw that request before the announcement. `PriorityRespected` then kept a phantom waiter
   and reported N2 violations on the final model; `NoHeadOnConflict` judged a direction that had already
   reversed. Both monitors were changed to account for this: they remember early withdrawals, and they
   take the direction at request time.
2. **`p check -tc` matches by prefix** (`results-round2-prefix-collisions.tsv`). `-tc tcE9Abort` also
   ran `tcE9AbortBreaksL2`, and the script recorded the second test's failure as the first one's.
   Tests were renamed so that no name is a prefix of another, and a check for this runs whenever the
   list changes.
3. **Fairness window too wide** (`results-round3-fairness-window.tsv`). The first fairness monitors
   charged a task with every delay up to the robot's abandonment. In a trace of the E7 excusal remedy,
   both deadlines expired *before* V2 started. The robot, sanctioned but not yet aware of it, was then
   evacuated, and the monitor counted that evacuation. A delay after the deadline expired cannot have
   caused the sanction, so the window now closes at `eDeadlineExpired`.
4. **Several early withdrawals in a row** (`results-round4-before-N2-monitor-fix.tsv`). The fix in item 1
   remembered one early withdrawal per robot and zone. At 100,000 schedules (after 26,125) and in E8, a
   robot withdrew *two* requests before either denial was announced, and the second overwrote the first.
   It now keeps every one. Replaying both failing schedules after the fix no longer reproduces a bug,
   while a control schedule (E10) still does.

Items 1 and 4 could only add false alarms: a missed or stale entry made the monitor stricter, never more
lenient. Passing results from earlier rounds therefore still hold; the final round re-ran everything
anyway.

---

## 4. Experiments

### E0 Monitor sanity: every monitor can fail

**Command:** `python3 -I experiments/run_mutants.py 10000 1`. For each mutant, the script copies the
model to `.mutants/<name>/`, applies an exact text replacement, adds a probe test with **only** the
target monitor, compiles, and runs `p check -tc tcProbe -s 10000 --seed 1`.

**Prediction:** every mutant is killed by its monitor.

| Mutant | Monitor | Mutation | Scenario | Result | Schedules |
|---|---|---|---|---|---|
| M01_N1 | ZoneMutualExclusion | controller grants an occupied zone | random tasks | killed | 1 |
| M02_N5 | NoRobotWithHuman | no Zone 1 lockout (evacuation kept) | random tasks | killed | 1 |
| M03_N4a | SanctionOnlyAfterExpiry | on-time delivery sanctioned | random tasks | killed | 1 |
| M04_N4b | NoDoubleOutcome | late arrival also confirmed | short deadlines | killed | 16 |
| M05_L_task | EveryTaskResolved | expired task never sanctioned | short deadlines | killed | 1 |
| M06_L_robot | EveryRobotSettles | no return trip after cooldown | short deadlines | killed | 1 |
| M07_L_human | HumanEventuallyEnters | human never admitted | random tasks | killed | 1 |
| M08_N2 | PriorityRespected | N2 reversed | random tasks | killed | 4 |
| M09_N2empty | EmptyRobotHasPriorityZero | empty robot keeps its priority | short deadlines | killed | 1 |
| M10_N3 | OutrankedOccupantPreempted | never preempt | random tasks | killed | 1 |
| M11_N7 | DeadlinesKeepRunning | deadline counts every other tick | random tasks | killed | 1 |
| M12_N8 | V1EventuallyRestored | V1 never restored | random tasks | killed | 1 |
| M13_L3 | AdaptationTerminates | switch neither commits nor aborts | E9 | killed | 2 |
| M14_E9admit | AbortNeverAdmits | aborted switch admits the human | E9 | killed* | 3 |
| M15_E9unblock | AbortUnblocksControllers | abort leaves controllers on V2 | E9 | killed | 3 |

\* **M14 first survived.** `AbortNeverAdmits` originally learned of an abort from the refusal sent to the
human. A coordinator that sends a grant *instead of* the refusal was invisible to it, and the checker
stopped on an unhandled event elsewhere instead. The monitor now keys on the coordinator's own
`eAdaptationAborted`, and the mutant is killed. This is the kind of weakness E0 exists to catch.

The table above is the run with the final monitors (`experiments/mutants.tsv`). The remaining monitors
fail on the final model itself, by design, so they need no mutant: `SanctionDuringV2` (property 4),
the two fairness monitors (E3), `NoHeadOnConflict` (E6) and `BayCapacityOne` (E10).

### Calibration of the schedule count (spec 5.9)

How many schedules does the checker need to find a known bug? Seeds 1–10, `-s 100000` (a run stops at
its first bug):

| Seeded bug | Command | Schedules to the first bug, seeds 1–10 | Max |
|---|---|---|---|
| naive coordinator (E2) | `p check -tc tcNaiveAdaptation -s 100000 --seed <n>` | 6, 3, 1, 2, 1, 1, 1, 4, 1, 4 | 6 |
| property 4 witness | `p check -tc tcCoverSanctionInV2 -s 100000 --seed <n>` | 1 in all ten | 1 |
| no lockout (M02_N5) | `run_mutants.py 100000 1,…,10 M02_N5` | 1, 1, 2, 2, 1, 1, 1, 1, 1, 1 | 2 |
| never preempt (M10_N3) | `run_mutants.py 100000 1,…,10 M10_N3` | 1, 1, 1, 1, 2, 1, 1, 1, 1, 1 | 2 |
| N2 reversed (M08_N2) | `run_mutants.py 100000 1,…,10 M08_N2` | 4, 8, 7, 9, 12, 1, 17, 6, 1, 3 | 17 |

Every seeded design defect is found within 20 schedules. `-s 10000` is therefore at least 500 times the
worst observed, and `-s 100000` (E1) at least 5,000 times. **But** the rarest event observed, the
monitor artifact of §3 item 4, needed 26,125 schedules under seed 1. Interleavings that deep exist in
this model, so a bug that requires one could be missed at `-s 10000`. That is the argument for
`-s 100000` on the baseline, and the reason "0 bugs" is never stated without its count.

### E1 Baseline (the final model)

All safety and liveness monitors attached (`TestScript.p`).

| Test case | Setup | Command | Prediction | Result |
|---|---|---|---|---|
| `tcHeadOnV1` | R1 A→B P4, R2 B→A P8, deadlines 15, no human | `p check -tc tcHeadOnV1 -s 100000 --seed 1` | hold | 0 bugs, 30 timelines, 1,008 s |
| `tcHumanAdaptation` | same + human (arrives within 10 steps, stays 1–10) | `p check -tc tcHumanAdaptation -s 100000 --seed 1` | hold | 0 bugs, 540 timelines, 2,444 s |
| `tcRandomTasks` | priority 1–10, deadline 1–15, infractions 0–1, human | `p check -tc tcRandomTasks -s 100000 --seed 1` | hold | 0 bugs, 2,962 timelines, 2,257 s |

At `-s 10000`, seed 1: `tcHeadOnV1` 0 bugs (19 timelines), `tcHumanAdaptation` 0 bugs (299),
`tcRandomTasks` 0 bugs (1,199). The 100,000-schedule runs ran in parallel with the rest of the final
round, so their times reflect a loaded machine.

`tcHeadOnV1` has few distinct timelines (30 in 100,000 schedules) because its tasks are fixed and there
is no human. Its scenario is small, and more schedules add little. The variation lives in
`tcRandomTasks`, whose distinct timelines kept growing (1,199 at 10,000, 2,962 at 100,000).

### E2 Naive adaptation

`p check -tc tcNaiveAdaptation -s 10000 --seed 1`. **Prediction:** `NoRobotWithHuman` fails.
**Result:** fails at schedule 6. Trace: `evidence/tcNaiveAdaptation_s10000.trace.txt`.

1. **Setup.** R1 P4, R2 P8, deadlines 15, human; the coordinator admits the human right after
   broadcasting V2. P 3.1.0.0, seed 1, random strategy.
2. **Violated property.** `NoRobotWithHuman`: "N6 violated: the human entered zone 1 while robots
   (<1>) are inside" (N5/N6, PDF property 2).
3. **Shortest prefix** (other machines omitted). Human → `eHumanRequest`; coordinator broadcasts V2 and
   immediately sends `eHumanAccessGranted`; R1 is still in Zone 1 (controller 1 has sent `ePreempt` but
   R1 has not retreated); the human announces `eHumanEnter`.
4. **Root cause.** Admitting the human does not wait for controller 1's evacuation ack. With seeds 5, 7, 8
   and 9 the other variant appears: a robot enters Zone 1 after the human (controller 1 had not yet
   installed V2).
5. **Real or artifact.** Real for any coordinator that grants access on its own broadcast.
6. **Fix.** The final model's two-phase switch: controller 1 acks V2 only once Zone 1 is empty.
7. **Regression.** E1 (`tcHumanAdaptation`, `tcRandomTasks`): `NoRobotWithHuman` holds.

### Property 4 (cover): a sanction while V2 is active

`p check -tc tcCoverSanctionInV2 -s 10000 --seed 1`. **Prediction:** witness found. **Result:**
witness at schedule 1, and at schedule 1 for every seed 1–10. Trace:
`evidence/tcCoverSanctionInV2_s10000.trace.txt`. R1 is evacuated from Zone 1 to Bay 1 (N6), the human
enters, and a robot's deadline expires under V2 (N7). This is slide 13's obligation-vs-adaptation
conflict, so property 4 is covered.

### E3 Sanction fairness

The refined fairness monitors (`PSpec/Fairness.p`) classify every delay a robot suffers by its cause:

| Class | Cause | Reported by | Norm |
|---|---|---|---|
| regulation | `CLOSED`: Zone 1 locked | `eAccessDenied` | N5 |
| regulation | `EVACUATED`: pushed out for the human | `ePreemptIssued` | N6 |
| regulation | `DIRECTION`: waiting for the travel direction | `eDirectionDenied` | E6 only |
| traffic | `OCCUPIED`: zone held by the other robot | `eAccessDenied` | N1 |
| traffic | `OUTRANKED`: pushed out by a higher priority | `ePreemptIssued` | N3 |

A delay counts against a task from its assignment until its deadline expires (or it is delivered or
abandoned). `NoRegulationCausedSanction` and `NoTrafficCausedSanction` each fail when a sanctioned task
suffered a delay of their class.
- **Order independence.** The verdict is checked whenever the second of the two facts arrives (the
  sanction or the delay), so it does not depend on which is observed first. This is the kit's "order
  sensitivity" requirement.
- **Candidate, not cause.** Like the kit's F1, these flag *candidate* unfair sanctions. A delay of a
  class during the task does not prove that delay made the robot miss its deadline.

Scenario: short deadlines (3–6 ticks), human arriving within 3 steps and staying up to 20.

| Test case | Command | Prediction | Result |
|---|---|---|---|
| `tcE3FairnessRegulation` | `p check -tc tcE3FairnessRegulation -s 10000 --seed 1` | fail | fails at schedule 1 |
| `tcE3FairnessTraffic` | `p check -tc tcE3FairnessTraffic -s 10000 --seed 1` | fail | fails at schedule 2 |
| `tcE3TrafficNoHuman` | `p check -tc tcE3TrafficNoHuman -s 10000 --seed 1` | fail, with no regulation delay | fails at schedule 1; the trace has no `CLOSED`/`EVACUATED` event |

**Regulation-caused** (`evidence/tcE3FairnessRegulation_s10000.trace.txt`):
1. **Setup.** R1 P5 deadline 6, R2 P7 deadline 4, human; seed 1.
2. **Violated property.** `NoRegulationCausedSanction`: task 2 sanctioned after a `CLOSED` delay.
3. **Prefix.** The human requests Zone 1; V2 is broadcast. R1 enters Zone 0 and R2 enters Zone 2. Both
   ask for Zone 1 and are denied `CLOSED` (locked). The human enters. R2's deadline (4 ticks) expires
   while it waits; it is sanctioned.
4. **Root cause.** N5 + N7: the regulation blocks the only way forward, and the deadline keeps running.
5. **Real or artifact.** Real; it is the case of slide 13, which the PDF accepts as a conflict.
6. **Fix.** Remedy E7.
7. **Regression.** E7, `tcE7SuspendExcuseShort` and `tcE7SuspendExcuseRandom`.

**Traffic-caused** (`evidence/tcE3FairnessTraffic_s10000.trace.txt`):
1. **Setup.** R1 P4 deadline 4, R2 P2 deadline 3, human; seed 1.
2. **Violated property.** `NoTrafficCausedSanction`: task 2 sanctioned after an `OUTRANKED` delay.
3. **Prefix.** R1 holds Zone 1 and asks for Zone 2, held by R2. R1 outranks R2 (P4 > P2), so
   controller 2 orders R2 to retreat to Bay 2 (N3). R2's deadline (3 ticks) expires.
4. **Root cause.** The head-on conflict itself: N2/N3 resolve it in R1's favour, at the cost of R2's time.
5. **Real or artifact.** Real. This trace also contains a `CLOSED` denial of R2 at Zone 1, so task 2 is
   flagged by **both** monitors. To show a traffic-only case, `tcE3TrafficNoHuman` repeats the scenario
   without the human, where no regulation delay is possible.
6. **Fix.** Remedy E6 targets head-on conflicts; E7 does not target traffic.
7. **Regression.** E6 (`tcE6FairnessTraffic`).

**Traffic only** (`evidence/tcE3TrafficNoHuman_s10000.trace.txt`):
1. **Setup.** Short deadlines, no human: R1 P5 deadline 6, R2 P7 deadline 4; seed 1.
2. **Violated property.** `NoTrafficCausedSanction`: task 2 sanctioned after an `OCCUPIED` delay. The
   trace contains no regulation delay at all.
3. **Prefix.** R1 enters Zones 0 and 1, R2 enters Zone 2. R2 asks for Zone 1, held by R1, and is denied
   (`OCCUPIED`). R2 outranks R1, so controller 1 orders R1 back to Bay 1 (N3). R2 then crosses Zones 1
   and 0, but its 4-tick deadline expires on the way.
4. **Root cause.** R2 **won** the conflict and is still the robot sanctioned: waiting for the loser to
   retreat used up its time. N2/N3 decide who passes, not who keeps the deadline.
5. **Real or artifact.** Real; no regulation is involved.
6. **Fix.** E6 removes head-on meetings. Neither remedy restores the winner's lost time.
7. **Regression.** `tcE6FairnessTraffic`: 0 bugs at 10,000.

Both causes occur. The cause of a candidate case can be read directly from the monitor's message.

### E4 Every controller blocks during the switch

| Test case | Switch | Command | Prediction | Result |
|---|---|---|---|---|
| `tcE4BlockAllParking` | `blockAll`, bays | `p check -tc tcE4BlockAllParking -s 10000 --seed 1` | hold | 0 bugs, 1,225 timelines |
| `tcE4BlockAllNoParking` | `blockAll`, no bays | `p check -tc tcE4BlockAllNoParking -s 10000 --seed 1` | fail `HumanEventuallyEnters` | fails at schedule 3 |

This matches the kit's prediction, "L2 holds only with parking". With side bays, every controller can
evacuate its zone, so the switch completes and safety is preserved. Without bays, a robot inside a locked
zone cannot leave, the controllers never ack, and the human waits forever. PChecker reports a "potential
liveness bug" after the run keeps going (the clock keeps ticking) with `HumanEventuallyEnters` hot.

### E5 No parking

`p check -tc tcE5NoParking -s 10000 --seed 1`. **Prediction:** `HumanEventuallyEnters` fails by circular
wait. **Result:** fails at schedule 3 (`evidence/tcE5NoParking_s10000.trace.txt.gz`, gzipped: 6.8 MB of clock ticks).
1. **Setup.** No bays; only Zone 1 locks (as in the final model); random tasks, seed 1: R1 P5, R2 P3.
2. **Violated property.** `HumanEventuallyEnters` (the kit's L2) stays hot.
3. **Prefix.** R2 holds Zone 1 and asks for Zone 0; R1 holds Zone 0 and asks for Zone 1. R1 outranks
   R2, so controller 1 orders R2 out (N3), but R2 has no bay and stays. V2 is then broadcast, and
   controller 1 waits for Zone 1 to empty before acking. Both robots are sanctioned but, without bays,
   keep their zones.
4. **Root cause.** A circular wait. Each robot holds the zone the other needs, and without a bay N3 and
   N6 cannot be executed.
5. **Real or artifact.** Real for a corridor without pull-outs. The side bays of the PDF are what make
   N3 and N6 executable.
6. **Fix.** Bays (the final model).
7. **Regression.** E1.

### E6 Remedy 1: one travel direction at a time

| Test case | Command | Prediction | Result |
|---|---|---|---|
| `tcE6HeadOnInBaseline` (final model) | `p check -tc tcE6HeadOnInBaseline -s 10000 --seed 1` | fail `NoHeadOnConflict` | fails at schedule 1 |
| `tcE6OneDirection` | `p check -tc tcE6OneDirection -s 10000 --seed 1` | hold (all baseline monitors + no head-on) | 0 bugs, 1,473 timelines |
| `tcE6FairnessTraffic` | `p check -tc tcE6FairnessTraffic -s 10000 --seed 1` | fail (same-direction congestion) | **0 bugs**, 882 timelines |
| `tcE6FairnessRegulation` | `p check -tc tcE6FairnessRegulation -s 10000 --seed 1` | fail (entrance waits, closure) | fails at schedule 1 |

- **Head-on conflicts disappear.** `NoHeadOnConflict` fails at once on the final model and holds with the
  remedy, together with every baseline monitor.
- **Prediction refuted for traffic.** No traffic-caused sanction was found in 10,000 schedules. The
  prediction assumed a returning robot and a delivering robot travelling the same way could congest. With
  two robots and one task each, the checker did not produce it in this scenario. We report the
  refutation as observed, at `-s 10000`, and do not claim it cannot happen.
- **The remedy trades one cause for another.** `NoRegulationCausedSanction` still fails: waiting at the
  entrance for the direction (`DIRECTION`) and the Zone 1 closure (`CLOSED`) remain.

### E7 Remedy 2: suspend deadlines during V2, excuse affected tasks

| Test case | Remedy | Command | Prediction | Result |
|---|---|---|---|---|
| `tcE7SuspendOnly` | `SUSPEND` | `p check -tc tcE7SuspendOnly -s 10000 --seed 1` | fail regulation-caused | fails at schedule 4 |
| `tcE7SuspendExcuseShort` | `SUSPEND_EXCUSE` | `p check -tc tcE7SuspendExcuseShort -s 10000 --seed 1` | hold | 0 bugs, 440 timelines |
| `tcE7SuspendExcuseRandom` | `SUSPEND_EXCUSE`, random tasks | `p check -tc tcE7SuspendExcuseRandom -s 10000 --seed 1` | hold | 0 bugs, 1,061 timelines |
| `tcE7Traffic` | `SUSPEND_EXCUSE` | `p check -tc tcE7Traffic -s 10000 --seed 1` | fail traffic-caused | fails at schedule 3 |
| `tcE7ReplacesN7` | `SUSPEND` | `p check -tc tcE7ReplacesN7 -s 10000 --seed 1` | fail `DeadlinesKeepRunning` | fails at schedule 1 |

Both stages behave as the kit predicts:
- **Suspension alone still fails** (`evidence/tcE7SuspendOnly_s10000.trace.txt`). R2 was held back at
  the locked Zone 1 during V2. After V1 returns, R1 is admitted to Zone 1 first and outranks R2 out of
  Zone 2, and R2's deadline expires after V2 has ended. Pausing the clock does not give back the robot's
  place in the corridor.
- **With excusal**, no regulation-caused sanction remains, and every safety and liveness monitor still
  holds, in both scenarios.
- **The remedy is sound by construction.** The coordinator tells the Fleet Manager that V2 starts and
  *waits for its ack* before any controller can deny a robot because of V2, so every regulation-caused
  delay happens inside a V2 episode that the Fleet Manager knows about.
- **What it does not fix.** Traffic-caused sanctions remain (`tcE7Traffic`).
- **The remedy changes the norms: it replaces N7.** `tcE7ReplacesN7` confirms that deadlines really stop
  under V2, which is why `DeadlinesKeepRunning` is not attached to the remedy's passing tests.

### E8 Scale

| Test case | Size | Command | Result |
|---|---|---|---|
| `tcRandomTasks` | 2 robots, 3 zones | `p check -tc tcRandomTasks -s 10000 --seed 1` | 0 bugs, 1,199 timelines |
| `tcE8ThreeRobots` | 3 robots, 3 zones | `p check -tc tcE8ThreeRobots -s 10000 --seed 1` | 0 bugs, 2,254 timelines, 281 s |
| `tcRandomTasks@4zones` | 2 robots, 4 zones | `experiments/run_scale.sh 10000 1 4` | 0 bugs, 1,071 timelines, 220 s |
| `tcE8ThreeRobots@4zones` | 3 robots, 4 zones | `experiments/run_scale.sh 10000 1 4` | 0 bugs, 1,906 timelines, 249 s |

The 2-robot, 3-zone row is `tcRandomTasks` at 10,000 schedules: 0 bugs, 1,199 timelines, 216 s. Every
size attaches all twelve baseline monitors.

**Prediction:** no bug, slower per schedule, more distinct timelines. The kit predicted "run time grows
rapidly". **Result:**
- **No bug in any size.**
- **More distinct timelines** with a third robot (1,199 → 2,254).
- **But only modestly more time** per 10,000 schedules (216 s → 281 s). A fourth zone barely changed
  anything.

So the "grows rapidly" part is **not** confirmed at this size. Two caveats:
- These runs shared the machine with the rest of the final round, so the times are rough.
- PChecker *samples* a fixed number of schedules, so its run time grows with the length of a schedule,
  not with the size of the state space. Coverage is what degrades: the same 10,000 schedules spread
  over many more interleavings, so each one is less likely to be hit. That is the cost of scale here.

### E9 Timeout and abort of the switch

| Test case | Command | Prediction | Result |
|---|---|---|---|
| `tcE9AbortSafety` | `p check -tc tcE9AbortSafety -s 10000 --seed 1` | hold: L3, abort never admits, abort unblocks, S1/S2 | 0 bugs, 3,438 timelines |
| `tcE9AbortBreaksL2` | `p check -tc tcE9AbortBreaksL2 -s 10000 --seed 1` | fail `HumanEventuallyEnters` by design | fails at schedule 3 |

The kit's three acceptance cases:

| Acceptance case | Evidence |
|---|---|
| a timeout followed by an abort satisfies L3 | `tcE9AbortSafety` |
| a switch neither committed nor aborted violates L3 | mutant M13_L3, killed |
| an aborted switch never admits the picker and leaves no controller blocked | `tcE9AbortSafety`, plus mutants M14 and M15, killed |

**Modeling note.** The timeout is nondeterministic, not "after k ticks": the coordinator has no clock.
This over-approximates any k.

### E10 Finite side bays (optional)

`p check -tc tcE10BayCapacity -s 10000 --seed 1`. **Prediction:** `BayCapacityOne` fails. Our corridor
lets two retreats meet in Bay 1; the kit's prediction for one finite bay per zone was "as E1". **Result:**
fails at schedule 22 (`evidence/tcE10BayCapacity_s10000.trace.txt`). R1 is outranked by R2 and retreats
to Bay 1 (N3). R2 enters Zone 1, and the V2 evacuation then sends R2 to Bay 1 as well (N6). So the
PDF's bays must hold two robots, or N3 and N6 need a rule for a full bay.

(b) and (c), bays only at the corridor ends, are **not run**. The PDF's corridor has a bay beside every
zone, and moving them is a different system.

---

## 5. Not covered here

- **Run time (PObserve).** No log format, parser, logs, fault injection or sanction counts by cause.
  The image cannot build PObserve (README §4). This is the assignment's 15% run-time component.
- **Writing.** The D1 note, the article draft and the presentation.
- **Exhaustive exploration.** PChecker samples schedules; every "0 bugs" is relative to its `-s`.
