# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Coursework in the [P language](https://p-org.github.io/P/) (state-machine modeling and model checking for
distributed/concurrent systems), plus graduate projects that apply P and **PObserve** (P's runtime log
monitor) to verify norm-based regulation in multi-agent systems. Two independent pieces:

- `P-Tutorial/` — a from-zero tutorial (`ClientServer.p`, `LockServer.p`), also published as a browsable page
  at `docs/index.html` (GitHub Pages).
- `Projects/ProjectRobot2026/` — the active graduate project: a mobile robot fleet crossing a shared corridor,
  with distributed admission control and centralized adaptation/sanctioning. `Projects/ProjectManufacturingCell2026/`
  is the sibling project (same architecture, a manufacturing cell instead of a corridor); check `git status`/`ls`
  before assuming it's present, since it has been in flux.
- `reviews/` — independent-evaluation writeups (e.g. `reviews/evaluation-2026-10-21/`) that distinguish *actual*
  tool output from *hypothesized* results in the project docs. `REPORT_TEMPLATE.md` is the template for a joint
  Claude+Codex review report; follow its structure (snapshot/scope, agreed findings, disagreements, verification
  performed, recommended actions, decisions for the user) when producing that kind of report.

Each project folder is a **self-contained P solution** — always `cd` into it before running `p`.

## Commands

From inside `P-Tutorial/` or `Projects/ProjectRobot2026/MobileRobots/` (same pattern for the manufacturing-cell
equivalent):

```bash
p compile                              # builds PGenerated/ from the .pproj's InputFiles
p check -tc <testcase> -s <N>          # model-check one test; -s = number of schedules
p check -tc <testcase> -i <N>          # older/tutorial form: -i = number of iterations
p check -tc <testcase> --replay <seed> # step through a specific counterexample
p compile --mode pobserve              # generate the PObserve Java parser from the same monitors
```

Requires .NET SDK **8.0** exactly and Java 11+ (`dotnet tool install --global P`). `PGenerated/` and
`PCheckerOutput/` are build output, gitignored, regenerated every run — never hand-edit or commit them (an
exception: a `.sci`/trace file worth preserving as documented evidence, as under `reviews/*/evidence/`).

Real test case names and required schedule counts live in each project's `PTst/TestScript.p` and
`INSTRUCTIONS.md`/`ASSIGNMENT.md` — check those before inventing a command. For `ProjectRobot2026`:

```bash
cd Projects/ProjectRobot2026/MobileRobots
p compile
p check -tc tcFleetTwoPhase         -s 100000   # baseline, two-phase adaptation: expect no bug
p check -tc tcFleetNaive            -s 10000    # naive adaptation: expect S1/S2 counterexample
p check -tc tcFleetSanctionFairness -s 10000    # expect F1 counterexample (intended, see below)
```

PObserve (runtime monitoring on logs) lives under each project's `MobileRobots/pobserve/` (or
`ManufacturingCell/pobserve/`), a separate Gradle package:

```bash
cd Projects/ProjectRobot2026/MobileRobots/pobserve
gradle wrapper && ./gradlew build     # p compile --mode pobserve, Java parser, JUnit
./gradlew uberjar
./run_pobserve.sh [log] [monitorName] # defaults to the naive sample log, all monitors
```

No Gradle wrapper is committed as of this writing (`gradle wrapper` must be run once with Gradle installed) —
don't assume the Java/PObserve side has ever actually been built in this environment; check the project's
`README.md` "Status" section first.

Generate synthetic logs without the Java toolchain:

```bash
python3 tools/simulate_logs.py --scenario fleet --policy naive --seed 2 --out fleet.log --check
```

`--check` runs a Python mirror of the P monitors over the generated log — useful for a quick sanity check, but
it is **not** PObserve; don't cite it as a PObserve result.

## Architecture (ProjectRobot2026, mirrored by ProjectManufacturingCell2026)

The regulation model follows a **hybrid grid-cell** split (Yan et al., COINE 2025): admission is regimented
*in a distributed way*, one guard per resource; adaptation and sanctioning are *centralized*.

| Machine | Role | Where |
|---|---|---|
| `ResourceGuard` (one per zone) | admits/denies access from local occupancy + its installed norm set | distributed |
| `AdaptationCoordinator` (one) | runs prepare/commit of a new norm set across every guard | centralized |
| `ObligationManager` (one) | creates, fulfills, sanctions deadline-bound obligations | centralized |
| `Clock` (one) | logical tick source, subscribed to only by `ObligationManager` | centralized |
| `HumanRequester` | triggers the adaptation that closes a zone for a human | — |
| `Robot` (`PSrc/Robot.p`) / `CellAgent` | the agent moving through zones, denial/parking/abandon policy | — |

Shared code lives in `Common/` (`Types.p`, `MonitorEvents.p`, the five machines above, `Specs.p`,
`RuntimeSpecs.p`); the project-specific folder (`MobileRobots/` or `ManufacturingCell/`) adds only `PSrc`
(wiring/topology), `PSpec` (one extra fleet/cell-specific monitor), and `PTst` (test cases). `.pproj` files
list `Common/` plus the local `PSrc/PSpec/PTst` as `InputFiles` — adding a new `.p` file means adding it there.

**Two monitor layers, same event vocabulary (`MonitorEvents.p`), different mechanics:**

- *Design time* (`Specs.p`, checked by `p check`): S1 `RegimentationSafety` (capacity + no-human-and-agent
  co-occupancy), S2 `NoStaleAdmission` (a guard never admits against an already-committed newer norm set), S3
  `NoDoubleOutcome` (an obligation is never both fulfilled and sanctioned), plus liveness monitors with `hot`
  states — L1 `EveryObligationResolved`, L2 `AdaptationCompletes`, L3 `AdaptationTerminates`.
- *Run time* (`RuntimeSpecs.p`, checked by PObserve on logs): R1 `ObligationDeadlineRespected` and R2
  `AdaptationBoundedTime` restate the two liveness monitors as **bounded-response safety** (a finite log can't
  prove "eventually," only "within N ticks") — R1 allows 1 tick grace, R2 allows 5. R3 `LockoutBeforeEntry` has
  no liveness equivalent and is checked at both design time and run time without modification. R1/R2 are
  deliberately *not* wired into the checker tests (`eTick` ordering there would raise false alarms).
- The project-specific monitor (e.g. `SanctionsReflectMisconduct` / F1 in `PSpec/FleetSpecs.p`) correlates two
  events by shared id (abandon → later sanction of the *same* obligation) and is explicitly scoped: it flags a
  *candidate* unfair sanction, not a proven causal one — it can't tell a regulation-caused denial from a
  traffic-caused one. Preserve that distinction when writing about it; don't upgrade "flagged" to "caused" in
  reports or docs.

**Test cases wire a *subset* of monitors into a scenario** via `assert <Monitor1>, <Monitor2> in { <machines> };`
in `PTst/TestScript.p` — a monitor not listed there is dead code for that test, and a monitor not `observe`-ing
an event it needs will fail to compile, not fail silently. When a test's failure is intended (e.g.
`tcFleetSanctionFairness`), the comment above it says so — don't treat an intended counterexample as a
regression.

## Evidence discipline (applies to any claim about this project)

This codebase's docs are strict about the difference between *observed result* and *hypothesis/prediction*:
"no bug found in N schedules" is a reportable result, "the design is correct" is not, unless N is justified.
Project READMEs explicitly track a "Status" section stating exactly what has and hasn't been run, with tool
versions and schedule/seed counts. When editing or reporting on these projects:

- Don't state a `p check` or PObserve result without having actually run it (or citing where it was run,
  e.g. `reviews/<date>/evidence/`) — distinguish "the spec predicts X" from "running the command gave X."
  This matters doubly here: these files double as a verification record for a graded assignment.
  Yan, F. et al. — COINE 2025, is cited for the regulation-capability framing (`ASSIGNMENT.md`,
  `SPECIFICATION.md`); don't restate its claims as this repo's own results.
- A "no bug found" claim always needs its schedule count (`-s`); carry it along when citing the result.
