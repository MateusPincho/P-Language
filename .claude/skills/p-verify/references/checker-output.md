# Reading PChecker output

Every example here is real output from
`p check -tc tcFleetNaive -s 2000` on `Projects/ProjectRobot2026/MobileRobots`.

## Where output lands

```
<project>/PGenerated/                     compiler output (the .dll the checker runs)
<project>/PCheckerOutput/
├── BugFinding/                           first run
├── BugFinding0/                          later runs get a numeric suffix
├── BugFinding2/
│   ├── MobileRobots_0_0.txt              the human-readable trace  <- start here
│   ├── MobileRobots_0_0.trace.json       machine-readable trace
│   ├── MobileRobots_0_0.schedule         the schedule, for --replay
│   ├── MobileRobots.coverage.txt         state/event coverage
│   ├── MobileRobots.sci                  coverage info, preservable as evidence
│   └── MobileRobots_pchecker_summary.txt one-glance summary
```

**Runs do not overwrite each other** — they create `BugFinding`, then `BugFinding0`, `BugFinding2`, and so
on. So always pick the newest directory by mtime, and glob `BugFinding*`, not `BugFinding`:

```bash
ls -dt <project>/PCheckerOutput/BugFinding* | head -1
```

PeasyAI itself is inconsistent here: its `fix-bug` tool globs `BugFinding*` sorted by mtime, while
`checker_utils.py` globs `BugFinding` exactly and so reads a stale trace after the first run. If you are
comparing against PeasyAI output, check which one produced it.

Both directories are gitignored build output. The exception is a trace worth preserving as documented
evidence, which belongs under `reviews/<date>/evidence/`.

## The summary file

```
bugs:1
schedules:1
max_depth:51
time_seconds:0.12
memory_max_mb:0
```

`bugs:0` with a low `schedules` count is weak evidence. Check both numbers before reporting anything.

## A clean run

```
..... Schedule #200
... Checking statistics:
..... Found 0 bugs.
... Scheduling statistics:
..... Explored 200 schedules
..... Explored 28 timelines
..... Number of scheduling points in terminating schedules: 166 (min), 171 (avg), 184 (max).
```

**Timelines matter as much as schedules.** 200 schedules over 28 distinct timelines is real exploration;
200 schedules over 1 timeline means the checker kept walking the same path and the run proves almost
nothing. If min, avg and max scheduling points are all equal, there is only one behavior — likely because
the system deadlocks early or a driver is deterministic.

## A counterexample

```
..... Schedule #1
Checker found a bug.
... Emitting traces:
..... Writing PCheckerOutput/BugFinding/MobileRobots_0_0.txt
..... Writing PCheckerOutput/BugFinding/MobileRobots_0_0.trace.json
..... Writing PCheckerOutput/BugFinding/MobileRobots_0_0.schedule
..... Found 1 bug.
..... Found 100.00% buggy schedules.
```

`100.00% buggy schedules` means every schedule explored hit it — the bug is not a rare interleaving, and
`-s 1` would have found it.

## The trace file

A line-by-line log, tagged by kind:

```
<TestLog>     Running test 'tcFleetNaive'.
<CreateLog>   PImplementation.RegimentationSafety was created.
<MonitorLog>  PImplementation.EveryObligationResolved enters cold state 'NoneOpen'.
<StateLog>    ... enters state '...'
<SendLog>     ... sent event ... to ...
<DequeueLog>  ... dequeued event ...
<ErrorLog>    Assertion Failed: ../Common/Specs.p:67:7 agent 1 admitted to resource 1,
              closed by committed norm set v1 (guard still on v0)
<StrategyLog> Found bug using 'random' strategy.
```

**Read `<ErrorLog>` first.** It names the failure and, for an assertion, the exact source location and
the message text — which is why writing a real message in every `assert` pays for itself. Then read
backwards from it to see how the system got there.

```bash
grep -n "ErrorLog" <bugfinding-dir>/*_0_0.txt
```

Monitors appear first in every trace, because they are created before the system starts. Confirming that
the monitors you expect are in the list is the quickest way to catch a test that forgot to assert one.

## Failure categories

`<ErrorLog>` text maps to four kinds, in the order worth working on them:

| Category | Looks like | Meaning |
|---|---|---|
| Unhandled event | `... received event ... that cannot be handled` | A state had no handler, `defer` or `ignore`. Usually a real modeling gap and the easiest to fix |
| Null target | `... sent to a null machine` / `Unhandled exception ... null` | A machine reference was used before it was assigned — normally a wiring or init-order bug |
| Assertion failure | `Assertion Failed: file:line:col message` | A safety property or a local `assert` was violated. This is the interesting one |
| Deadlock / liveness | `Deadlock detected` / a monitor left in a `hot` state | Nothing could proceed, or an obligation was never discharged |

**p-debug** has the remediation procedure for each.

## Replaying

```bash
.claude/skills/p-verify/scripts/pdock.sh <project-dir> check -tc <tc> --replay <seed>
```

Replay re-runs one specific schedule deterministically, which is how you confirm a fix addressed *this*
counterexample rather than just perturbing the schedule space. Re-running with a different `-s` can hide
a bug by exploring elsewhere; replay cannot.

After a fix: replay the original counterexample, then re-check at a low schedule count, then at the full
count. All three, in that order.
