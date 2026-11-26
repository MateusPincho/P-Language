# Warehouse Fleet 2026: Corridor Regulation in P

A P model of the regulation layer for two warehouse robots sharing a single-lane, three-zone corridor:
distributed zone controllers (N1–N3, N5, N6), a centralized Fleet Manager for obligations and sanctions
(N4, N7), and a centralized Adaptation Coordinator that switches the norm set V1 ⇄ V2 for a human
picker (N5, N6, N8).

- **Specification:** [`SPECIFICATION.md`](SPECIFICATION.md), derived from
  `docs/Multi-Robot Fleet in a Warehouse update.pdf`. It keeps the PDF's claims apart from our modeling
  decisions (§7).
- **Model:** [`WarehouseFleet/`](WarehouseFleet/), a standalone P project.
- **Experiments:** [`EXPERIMENTS.md`](EXPERIMENTS.md), the assignment's experiments E0–E10 mapped to
  this model: one section per experiment, with its test cases, commands, predictions and results.
- **Evidence:** [`evidence/`](evidence/), counterexample traces and replayable schedules for every test
  whose failure is intended.

## Layout

```
WarehouseFleet2026/
├── SPECIFICATION.md
├── EXPERIMENTS.md                 E0-E10: test cases, predictions, results
├── README.md
├── evidence/                      saved traces (PCheckerOutput/ is gitignored)
├── experiments/                   scripts and raw results of the experiments
│   ├── run_tests.sh               p check for a list of test cases, logs a line per run
│   ├── run_mutants.py             E0: one mutant per monitor, on a temporary copy
│   ├── run_scale.sh               E8: the model with 4 zones, on a temporary copy
│   ├── results.tsv  mutants.tsv   one line per run (earlier rounds kept alongside)
│   └── logs/                      the checker's output for every run
└── WarehouseFleet/                <- run p from here
    ├── WarehouseFleet.pproj
    ├── PSrc/   Enums_Types_Events.p  Robot.p  ZoneController.p  ObligationManager.p
    │           AdaptationCoordinator.p  HumanPicker.p  Clock.p
    │           DirectionGuard.p (E6 only)
    ├── PSpec/  Safety.p (properties 1-3, NoDoubleOutcome)
    │           Liveness.p (EveryTaskResolved, EveryRobotSettles, HumanEventuallyEnters)
    │           Cover.p (property 4, witness monitor)
    │           NormMonitors.p (N2, N3, N7, N8)
    │           Fairness.p (E3: regulation- vs traffic-caused sanctions)
    │           ExperimentMonitors.p (E6, E9, E10)
    └── PTst/   TestDriver.p  TestScript.p (24 test cases)
```

## 1. Set up the P toolchain in Docker (once)

Nothing is installed on the host: .NET 8, Java, and the `p` tool all live in the `p-language:latest`
image built from the repo's `Dockerfile`. You need Docker with the `compose` plugin and a few GB of disk
for the image.

From the **repo root** (`P-Language/`):

```bash
docker compose build         # first time only, or after editing the Dockerfile
docker compose run --rm p bash -lc 'p --version && dotnet --version && java -version'
```

The container user gets uid/gid 1000, so the files it writes into the repo are owned by you. If your
own ids are different (`id -u`, `id -g`), build with
`HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose build` instead.

The repo is mounted at `/workspace` inside the container and a shell starts there, so use paths
relative to the repo root (as every command below does).

The last command should print `P version 3.1.0.0` (the version used for the results below), a .NET
8 SDK version, and Java 11.

## 2. Open P in Docker

Both ways use the same image and the same bind-mounted repo, so files written by the container
(`PGenerated/`, `PCheckerOutput/`) appear in your working tree, owned by you.

**a) An interactive shell.** Recommended; every command in §3 is written for it:

```bash
docker compose run --rm p bash
# now inside the container, at the repo root
cd Projects/WarehouseFleet2026/WarehouseFleet     # always cd to the folder holding the .pproj
p compile
exit                                              # --rm deletes the container on exit
```

**b) One command at a time**, from the host. Wrap any `p` command from §3 like this:

```bash
docker compose run --rm p bash -lc 'cd Projects/WarehouseFleet2026/WarehouseFleet && p compile'
docker compose run --rm p bash -lc 'cd Projects/WarehouseFleet2026/WarehouseFleet && p check -tc tcHeadOnV1 -s 1000'
```

`p` looks for the `.pproj` in the **current folder**. Running `p compile` from
`Projects/WarehouseFleet2026/` (one level too high) fails or leaves a stray `PGenerated/` there.

## 3. Check the model yourself

Every command below is run **inside the container**, from
`Projects/WarehouseFleet2026/WarehouseFleet/` (§2a).

### 3.1 Compile and list the tests

```bash
p compile                 # expect: "Compilation succeeded."
p check --list-tests      # expect: the five test cases below
```

Compile again after every edit to a `.p` file: `p check` runs the last compiled build.

### 3.2 Run each test case

`TestScript.p` has 24 test cases. The five below are the original ones (the PDF's properties). The
other 19 belong to the assignment's experiments, and each is described, with its command, in
[`EXPERIMENTS.md`](EXPERIMENTS.md) §4. `p check --list-tests` lists them all.

**`-tc` matches test names by prefix.** `p check -tc tcE9Abort` would run every test whose name starts
with `tcE9Abort`. The names in `TestScript.p` are chosen so that none is a prefix of another; keep it
that way when you add a test.

`-tc` names the test case and `-s` the number of schedules. Add `--seed 1` to reproduce the final round
exactly (*Status*); without it, each run picks its own seed. These are the commands used for every
result in *Status*. Each count was run once: first `-s 1000`, then `-s 10000`, then `-s 100000` for the
three tests expected to pass. The `-o` folder keeps each run's output separate, which matters when
several tests run in parallel; without `-o`, everything goes to `PCheckerOutput/` and the next run
overwrites it.

#### Test case `tcHeadOnV1`: head-on conflict under V1, no human

R1 (A → B, priority 4) and R2 (B → A, priority 8), deadlines 15, COOLDOWN 2. Exercises N1–N4.
Monitors: `ZoneMutualExclusion`, `SanctionOnlyAfterExpiry`, `NoDoubleOutcome`, `PriorityRespected`,
`EmptyRobotHasPriorityZero`, `OutrankedOccupantPreempted`, `DeadlinesKeepRunning`, `EveryTaskResolved`,
`EveryRobotSettles`.

```bash
p check -tc tcHeadOnV1 -s 1000
p check -tc tcHeadOnV1 -s 10000  -o PCheckerOutput/tcHeadOnV1_s10000
p check -tc tcHeadOnV1 -s 100000 -o PCheckerOutput/tcHeadOnV1_s100000     # about 9 min
```

Expected: `Found 0 bugs.`

#### Test case `tcHumanAdaptation`: the same trip with the human picker (V1 → V2 → V1)

Same robots and tasks. The human asks for Zone 1 after 0–10 steps and stays 1–10 steps. Exercises
N1–N8. Monitors: the nine above plus `NoRobotWithHuman`, `HumanEventuallyEnters` and
`V1EventuallyRestored`.

```bash
p check -tc tcHumanAdaptation -s 1000
p check -tc tcHumanAdaptation -s 10000  -o PCheckerOutput/tcHumanAdaptation_s10000
p check -tc tcHumanAdaptation -s 100000 -o PCheckerOutput/tcHumanAdaptation_s100000   # about 28 min
```

Expected: `Found 0 bugs.`

#### Test case `tcRandomTasks`: random tasks, with the human picker

Priority 1–10, deadline 1–15 and initial infractions 0–1 for each robot, all chosen by the checker,
plus the human picker. Same twelve monitors as `tcHumanAdaptation`.

```bash
p check -tc tcRandomTasks -s 1000
p check -tc tcRandomTasks -s 10000  -o PCheckerOutput/tcRandomTasks_s10000
p check -tc tcRandomTasks -s 100000 -o PCheckerOutput/tcRandomTasks_s100000           # about 28 min
```

Expected: `Found 0 bugs.`

#### Test case `tcNaiveAdaptation`: a deliberately broken coordinator

The coordinator admits the human without waiting for Zone 1 to be evacuated. Monitors:
`ZoneMutualExclusion`, `NoRobotWithHuman`.

```bash
p check -tc tcNaiveAdaptation -s 1000
p check -tc tcNaiveAdaptation -s 10000 -o PCheckerOutput/tcNaiveAdaptation_s10000
```

Expected: `Found 1 bug.` from `NoRobotWithHuman` (property 2). **This failure is intended.** It shows
the monitor can catch a missing evacuation.

#### Test case `tcCoverSanctionInV2`: property 4 (cover)

Deadlines 3–6, the human arrives within 3 steps and stays up to 20. Monitor: `SanctionDuringV2` only.

```bash
p check -tc tcCoverSanctionInV2 -s 1000
p check -tc tcCoverSanctionInV2 -s 10000 -o PCheckerOutput/tcCoverSanctionInV2_s10000
```

Expected: `Found 1 bug.` from `SanctionDuringV2`. **This failure is the desired result.** P has no
cover construct, so the monitor fails when a sanction happens under V2, and the trace proves the
situation is reachable. `Found 0 bugs.` here would mean property 4 was *not* covered.

#### Timing and extra flags

At `-s 1000` each test takes 5–10 seconds, so start there. The two intended failures stop at the first
bug, in under a second.

Useful extra flags: `--seed <n>` makes a run reproducible, and `-t <seconds>` sets a timeout.

### 3.3 Read the result

The end of every run prints a summary:

```
..... Found 0 bugs.
..... Explored 100000 schedules
..... Explored 2947 timelines
..... Number of scheduling points in terminating schedules: 107 (min), 207 (avg), 345 (max).
```

- **Found N bugs.** 0 means no property was violated in the schedules explored. That is evidence, not a
  proof, and it always goes with its schedule count.
- **Explored N schedules.** How many interleavings were sampled (`-s`).
- **Explored N timelines.** How many of them were actually different. A low number (e.g. 33 for
  `tcHeadOnV1`) means the scenario has little nondeterminism, and more schedules add little.
- **terminating schedules.** Every run ended with both robots settled and the clock stopped. If runs
  stop terminating, a liveness monitor can be stuck in a `hot` state.

Output lands in `WarehouseFleet/PCheckerOutput/BugFinding/` (or your `-o` folder):

| File | Contents |
|---|---|
| `WarehouseFleet_0_0.txt` | the trace of the failing schedule (only when a bug is found) |
| `WarehouseFleet_0_0.schedule` | the same schedule, replayable |
| `WarehouseFleet.coverage.txt` | which (state, event) handlers ran, per machine |
| `WarehouseFleet_pchecker_summary.txt` | the summary above |

### 3.4 Read a counterexample

For example, after `p check -tc tcNaiveAdaptation -s 10000 -o PCheckerOutput/tcNaiveAdaptation_s10000`:

```bash
grep "<ErrorLog>" PCheckerOutput/tcNaiveAdaptation_s10000/BugFinding/*.txt     # which property failed, and where
grep -E "<AnnounceLog>|<ErrorLog>" PCheckerOutput/tcNaiveAdaptation_s10000/BugFinding/*.txt   # moves, in order
```

Without `-o`, the same files are in `PCheckerOutput/BugFinding/`.

`<AnnounceLog>` lines are the robots' and the human's physical moves (`eZoneEntered`, `eZoneLeft`,
`eHumanEnter`), so reading them top to bottom tells the story of the run. You can compare it with the
slides. The full trace also shows every message sent and every state change.

To step through a saved counterexample again (two are kept in `evidence/`):

```bash
p check -tc tcCoverSanctionInV2 --replay ../evidence/tcCoverSanctionInV2_s10000.schedule   # "Reproduced 1 bug."
p check -tc tcNaiveAdaptation   --replay ../evidence/tcNaiveAdaptation_s10000.schedule
```

The `-tc` must name the test case the schedule came from.

### 3.5 Make sure a passing test isn't empty

A test that passes because nothing happened proves nothing. After a run, check the coverage report. For
example, for test case `tcRandomTasks`:

```bash
p check -tc tcRandomTasks -s 1000
grep -E "^StateMachine|^Event coverage|^Total" PCheckerOutput/BugFinding/WarehouseFleet.coverage.txt
```

`tcHumanAdaptation` and `tcRandomTasks` reach 100% for every machine. Below 100%, the file lists the
handlers that never ran.

### 3.6 Try your own scenario

Each test is a small driver in `PTst/TestDriver.p` that passes a scenario tuple to `FleetScenario`:
priority (`p1`, `p2`), deadline (`d1`, `d2`), initial infractions (`v1`, `v2`), `cooldown`, whether the
human is present, and so on. To add a scenario, copy a driver machine, change the numbers, and add a
matching `test` line in `PTst/TestScript.p` with the monitors you want checked. Then compile and run it.
`choose(n)` (a value in `0..n-1`) lets the checker try every value instead of one.

### 3.7 Break a norm on purpose

This is the most direct way to see what the tests can and cannot catch: copy the model, break one norm
in the copy, and run the checker. If the broken model still passes, that norm is unchecked. Experiment
E0 does exactly this for every monitor, with a script. From `Projects/WarehouseFleet2026/` on the
host:

```bash
python3 -I experiments/run_mutants.py 10000 1            # all 15 mutants, seed 1
python3 -I experiments/run_mutants.py 10000 1 M08_N2     # one mutant: N2 reversed
```

Each mutant is an exact text replacement listed at the top of `run_mutants.py`. The script applies it
to a temporary copy in `.mutants/`, adds a probe test that attaches only the target monitor, then runs
`p compile` and `p check -tc tcProbe -s <N> --seed <seed>` in the container. It records `KILLED`,
`SURVIVED` or `OTHER-BUG` in `experiments/mutants.tsv`. Results are in `EXPERIMENTS.md`, E0: all 15
mutants are killed.

To try a mutation by hand, the same steps work inside the container. Start from
`Projects/WarehouseFleet2026/`, and keep the copy inside the repo so the container can see it
(`.mutants/` is gitignored):

```bash
mkdir -p .mutants && cp -r WarehouseFleet .mutants/handrun && cd .mutants/handrun
rm -rf PGenerated PCheckerOutput
sed -i 's/return a.priority > b.priority;/return a.priority < b.priority;/' PSrc/ZoneController.p
grep -n "a.priority < b.priority" PSrc/ZoneController.p   # check the sed really changed the file
p compile
p check -tc tcRandomTasks -s 3000 --seed 1     # Found 1 bug, at schedule 2
cd ../.. && rm -rf .mutants/handrun
```

On 2026-11-24 this run stopped at schedule 2 with "N3 violated: robot 1 (P=9) outranks robot 2 (P=7) in
zone 2, but no retreat was ordered". The first monitor to fire is the N3 one, because reversing the
controller's comparison also reverses its preemption decisions. E0's probe for this mutant attaches only
`PriorityRespected` and shows the N2 monitor catches it as well. Before the N2, N3, N7 and N8 monitors
were added (2026-11-23), this mutant and an N3 mutant passed 3,000 schedules with 0 bugs. That gap is
why those monitors exist.

## 4. PObserve (runtime monitoring of logs)

PObserve runs the **same P monitors** against log files from a running system, instead of against the
model. Its pipeline is: your log parser turns each log line into a P event, PObserve sorts the events by
timestamp, and it feeds them to the spec.

### 4.1 What works in this repo today

Generating the Java version of the monitors works in the container (run on 2026-11-23):

```bash
p compile --mode pobserve      # inside the container, from WarehouseFleet/
```

It writes `WarehouseFleet/PGenerated/PObserve/` with `PEvents.java`, `PTypes.java`, `PMachines.java`
(the monitors), a `pom.xml` and `FFIStubs.txt`. The Java package is `WarehouseFleet.pobserve`.
`FFIStubs.txt` is empty because the model has no foreign functions, so there is nothing to fill in. The
PChecker build in `PGenerated/PChecker/` is left in place.

### 4.2 What is missing

**Building and running PObserve has not been done here.** The image lacks what it needs:

- **JDK 17 or newer.** The image has a Java 11 runtime only, with no compiler. The generated `pom.xml`
  targets Java 17.
- **Gradle 8.x.** Not in the image.
- **The PObserve runtime and CLI jar.** The generated code imports `pobserve.runtime.*` and `prt.*`, but
  the generated `pom.xml` declares no dependency on them. They come from building PObserve from source
  (below).
- **A log parser.** Java code you write, specific to your log format.
- **Logs.** No robot fleet or simulator produces logs for this project yet.

### 4.3 Steps, per the official docs (not run here)

Source: the PObserve section of the P docs, https://p-org.github.io/P/advanced/pobserve/pobserve/
(Getting Started, Package Setup, Log Parser, PObserve CLI, and the Lock Server example). Follow the docs
where they differ from this summary.

1. **Build the PObserve CLI jar** (Java 17+, Gradle 8.x):
   ```bash
   git clone https://github.com/p-org/P.git
   cd P/Src/PObserve/PObserve
   gradle wrapper && ./gradlew build
   # -> build/libs/PObserve-1.0.0.jar
   ```
2. **Create a Gradle package** for the parser and specs (`gradle init --type java-library --dsl kotlin`).
   Put a copy of this model's monitors and types under `src/main/PSpec/`: `Enums_Types_Events.p` plus the
   `PSpec/*.p` files. Add a `.pproj` whose `<OutputDir>` points into `src/main/java/...`. Add a
   `compilePSpec` task that runs `p compile --mode pobserve` before `compileJava`, and the Shadow plugin
   for an `uberjar` task. The parser and the specs must end up in one jar. The Package Setup page has
   the full `build.gradle.kts`.
3. **Write the log parser.** It is a class implementing `Parser<PEvent>` with
   `Stream<PObserveEvent<PEvent>> apply(Object logLine)`. It returns one `PObserveEvent` (a partition
   key, a timestamp, the P event and the log line) per relevant line, or `Stream.empty()`. Don't use
   static fields; parsers run multi-threaded. For the exact `PObserveEvent` constructor, copy the
   `LockServerParser` example in the P repo. Building this project's events looks like this (class
   names checked against the generated code):
   ```java
   // a line such as {"ts":1712,"event":"eZoneEntered","robotId":1,"zone":0}
   PEvent e = new PEvents.eZoneEntered(new PTypes.PTuple_robot_zone(robotId, zone));
   PEvent h = new PEvents.eHumanEnter();          // no payload
   ```
4. **Build** with `./gradlew build && ./gradlew uberjar`.
5. **Run** it on a log, once per spec:
   ```bash
   java -jar PObserve-1.0.0.jar \
     --jars build/libs/<your-uberjar>.jar \
     --parser <your.package.YourParser> \
     --spec ZoneMutualExclusion \
     -l fleet.log \
     --inputKind json \
     --outputDir pobserve-out
   ```
   A pass prints `Success! No bugs found.` followed by event counts. A violation prints
   `PObserve Spec Violation::` with the assertion location and message, as in the checker (for example
   `PSpec/Safety.p:43 N6 violated: ...`), and writes a replay log to the output folder.

### 4.4 Which monitors make sense on logs, and what the log must contain

Use the **safety** monitors. A finite log cannot show that something "eventually" happens, so the
liveness monitors (`hot` states) do not translate directly. The cover monitor `SanctionDuringV2` would
flag every sanction during V2, which is allowed behavior (slide 13). On a log it works as a detector,
not as a check.

| Spec | Log must contain |
|---|---|
| `ZoneMutualExclusion` | `eZoneEntered`, `eZoneLeft` (robotId, zone) |
| `NoRobotWithHuman` | the above, plus `eHumanEnter`, `eHumanExit` |
| `SanctionOnlyAfterExpiry` | `eDeadlineExpired` (robotId, taskId), `eSanction` (robotId, taskId, cooldown, infractions) |
| `NoDoubleOutcome` | `eDeliveryConfirmed` (robotId, taskId), `eSanction` |

The timestamps have to order entries and exits correctly across robots, or `ZoneMutualExclusion` will
report false alarms.

## Status

**Final round: 2026-11-24, P 3.1.0.0** in `p-language:latest`, from `WarehouseFleet/`, seed 1, with the
commands of §3.2 and `EXPERIMENTS.md`. "0 bugs" means none in the stated number of schedules under
PChecker's default random strategy. It is evidence, not a proof of correctness.

### The final model (E1)

All twelve baseline monitors are attached: properties 1–3, `NoDoubleOutcome`, N2 ×2, N3, N7, N8 and three
liveness monitors (property 2 and the human/N8 monitors only where the human is present).

| Test case | Command | Result | Distinct timelines |
|---|---|---|---|
| `tcHeadOnV1` | `p check -tc tcHeadOnV1 -s 100000 --seed 1` | **0 bugs** | 30 |
| `tcHumanAdaptation` | `p check -tc tcHumanAdaptation -s 100000 --seed 1` | **0 bugs** | 540 |
| `tcRandomTasks` | `p check -tc tcRandomTasks -s 100000 --seed 1` | **0 bugs** | 2,962 |

The intended failures fail as intended:
- `tcNaiveAdaptation`: `NoRobotWithHuman` fails at schedule 6.
- `tcCoverSanctionInV2`: property 4 witnessed at schedule 1.

**Every monitor can fail (E0).** 15 mutants, one per monitor, are all killed at `-s 10000`; the other
monitors fail on the final model by design. **Schedule count (spec 5.9).** Seeded design bugs are found
within 1–17 schedules over seeds 1–10. Details are in `EXPERIMENTS.md` (E0 and calibration).

**The passing tests are not vacuous.** Every schedule terminated with both robots settled, so the liveness
monitors were judged on complete runs. In `tcHumanAdaptation` and `tcRandomTasks` (`-s 1000`, coverage
report), every handler of the final model ran at least once. The overall event coverage is 86.3% because
every handler that did not run belongs to an experiment switch:
- E4: `eNormCommit`;
- E5: `eCooldownOver` while travelling or done;
- E6: `AwaitDirection`;
- E7: the notices to the Fleet Manager;
- E9: `eAdaptTimeout` and `eHumanAccessRefused`.

### The experiments (E0–E10)

All 24 test cases and 15 mutants were run. Every result matches its prediction except two:
- `tcE6FairnessTraffic` (predicted to fail; 0 bugs at 10,000).
- E8's "run time grows rapidly" (no bug in any size, but only modestly slower).

The full table, the counterexample write-ups, and the problems found in the experimental setup itself
(three monitor false alarms and `-tc` prefix matching, none in the model) are in
[`EXPERIMENTS.md`](EXPERIMENTS.md). Raw records: `experiments/results.tsv`, `experiments/mutants.tsv`,
`experiments/logs/`. Traces: `evidence/` (the two large liveness traces are gzipped).

### History

The 2026-11-18 round ran the five original tests with the original seven monitors: 0 bugs at 100,000
schedules each for the three passing tests (33 / 558 / 2,947 timelines). That round found that reversing
N2 or removing N3 went unnoticed (0 bugs at 3,000). The N2, N3, N7 and N8 monitors were added on
2026-11-23 to close that gap (see E0).

### PObserve

`p compile --mode pobserve` generated the Java monitors without errors on 2026-11-23. Nothing beyond that
has been built or run (see §4.2 for what is missing).

### Not done

- No PObserve build or run on logs, and there are no logs to run it on: the run-time part of the
  assignment.
- No exhaustive exploration: PChecker samples schedules. The state space is finite but was not
  enumerated.
- `-s` counts above are what was run; no claim is made beyond them.
