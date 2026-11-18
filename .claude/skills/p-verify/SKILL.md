---
name: p-verify
description: Compile and model-check P projects with the containerized P toolchain. Use when asked to run p compile or p check, verify a P model, list a project's test cases, or interpret PChecker output and counterexample traces.
---

# Verifying P projects

The host has no P toolchain — no .NET SDK, no `p` on `PATH`. Everything runs in `p-language:latest`.
A bare `p compile` in a host shell fails with `command not found`.

## Running p

Use the wrapper:

```bash
.claude/skills/p-verify/scripts/pdock.sh <project-dir> compile
.claude/skills/p-verify/scripts/pdock.sh <project-dir> check --list-tests
.claude/skills/p-verify/scripts/pdock.sh <project-dir> check -tc <tcName> -s <N>
.claude/skills/p-verify/scripts/pdock.sh <project-dir> check -tc <tcName> --replay <seed>
.claude/skills/p-verify/scripts/pdock.sh <project-dir> compile --mode pobserve
```

`<project-dir>` is the directory containing the `.pproj`, not the repo root. The wrapper refuses a
directory with no `.pproj` and one outside the repo, because both fail in confusing ways otherwise. It
builds the image on first use.

Or go direct:

```bash
docker compose run --rm p bash -lc 'cd /abs/path/to/project && p compile'
```

Three things make that work, and all three are easy to get wrong:

- **Absolute host paths.** The repo is bind-mounted at the same absolute path it has on the host
  (`PROJECT_MOUNT` in the gitignored `.env`, here `/home/mateus/Projects/P-Language`), so a path means the
  same thing on both sides. Never pass `/workspace`.
- **`bash -lc`, a login shell.** `p` lives at `/home/dev/.dotnet/tools/p` and only a login shell has it on
  `PATH`.
- **`cd` into the `.pproj` directory first.** `p` searches the current folder for the project file.
  `Projects/ProjectRobot2026/PGenerated/` is leftover output from a compile run one level too high — that
  is the failure mode.

The container runs as uid/gid 1000, so `PGenerated/` and `PCheckerOutput/` land in the working tree owned
by you. Both are gitignored build output, regenerated every run. Never hand-edit or commit them. The one
exception is a trace worth preserving as documented evidence, which belongs under `reviews/<date>/evidence/`.

## Commands

| Command | Purpose |
|---|---|
| `p compile` | Build `PGenerated/` from the `.pproj`'s `InputFiles` |
| `p compile --strict-errors` (`-se`) | Abort on the first type error. Default since P 3.0 is to report all of them in one pass |
| `p check --list-tests` | List the test cases this project declares |
| `p check -tc <tc> -s <N>` | Model-check one test over N schedules |
| `p check -tc <tc> --replay <seed>` | Step through one specific counterexample |
| `p compile --mode pobserve` | Generate the PObserve Java parser from the same monitors |

`-s` is schedules. The older tutorial form `-i` is iterations. Carry whichever you used when reporting a
result.

A compile is successful on a zero exit status; `p` also prints `Compilation succeeded.`

## Workflow

1. `p compile`. On failure, hand off to **p-debug** — do not guess at the fix.
2. `p check --list-tests` to get the real test names. Do not invent them; they come from `PTst/`.
3. Run each test at a schedule count justified by what you are claiming.
4. On a counterexample, hand off to **p-debug** with the trace.

Before compiling at all, the static checker in **p-language** catches most syntax problems in a second
rather than a minute:

```bash
python3 -I .claude/skills/p-language/scripts/validate_p.py FILE.p --project PROJECT_DIR
```

## Project-specific commands

Real test names and required schedule counts live in each project's `PTst/TestScript.p` and its
`INSTRUCTIONS.md`/`ASSIGNMENT.md`. Check those before inventing a command. For `ProjectRobot2026`:

```bash
cd Projects/ProjectRobot2026/MobileRobots
p check -tc tcFleetTwoPhase         -s 100000   # baseline: expect no bug
p check -tc tcFleetNaive            -s 10000    # naive adaptation: expect an S1/S2 counterexample
p check -tc tcFleetSanctionFairness -s 10000    # expect an F1 counterexample (intended)
```

An intended counterexample is not a regression. The comment above such a test says so; believe it.

## Evidence discipline

These files double as a verification record for a graded assignment, so the standard is higher than
usual.

- **Never report a `p check` or PObserve result without having run it**, or without citing where it was
  run (e.g. `reviews/<date>/evidence/`). "The spec predicts X" and "running it gave X" are different
  claims.
- **"No bug found" always travels with its schedule count.** `-s 200` and `-s 100000` are not the same
  evidence. Carry the number every time the result is cited.
- **"No bug found in N schedules" is a result. "The design is correct" is not**, unless N is justified.
- Say when a result came from PeasyAI rather than a hand-run `p check`. PeasyAI's compile/check tools do
  shell out to the real `p`, so their output is genuine — but the provenance still belongs in the report.
- A test that passes because nothing ever happened proves nothing. Check the schedule and timeline counts
  in the summary, not just "Found 0 bugs."

Each project README has a Status section stating exactly what has and has not been run, with tool versions
and schedule or seed counts. Keep it current.

## PObserve

PObserve runtime monitoring lives under each project's `MobileRobots/pobserve/` as a separate Gradle
package. **`gradle` is not in the image**, so that build cannot run here — check the project README's
Status section before assuming it ever has.

`python3 tools/simulate_logs.py --scenario fleet --policy naive --seed 2 --out fleet.log --check` runs a
Python mirror of the P monitors over a generated log. Useful as a sanity check. It is **not** PObserve;
do not cite it as a PObserve result.

## Reading output

See [references/checker-output.md](references/checker-output.md) for where traces land, how to read the
summary and the `<ErrorLog>` line, and how to replay a counterexample.
