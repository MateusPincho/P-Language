---
name: p-debug
description: Diagnose and fix P compilation errors and PChecker counterexamples. Use when p compile fails, when a p check test case reports a bug, or when tracking down an unhandled event, deadlock, assertion failure, or liveness/hot-state violation in a P model.
---

# Debugging P models

Two loops: compile failures and checker counterexamples. Both are mechanical up to the point where you
have to decide what the model *should* do.

Related: **p-verify** runs the toolchain, **p-language** has the syntax rules, **p-project** has the
wiring rules.

## Compile failures

```bash
.claude/skills/p-verify/scripts/pdock.sh <project-dir> compile
```

1. **Run the static checker first.** It is seconds instead of a minute, and reports line numbers:
   ```bash
   python3 -I .claude/skills/p-language/scripts/validate_p.py FILE.p --project PROJECT_DIR
   ```
2. **Take the first error.** `p compile` reports all type errors in one pass by default since P 3.0
   (`--strict-errors`/`-se` restores abort-on-first), but later errors are often cascades of the first.
3. **Look it up** in [references/compile-errors.md](references/compile-errors.md) — 69 compiler messages
   keyed on the fragment you actually see. Grep it for a distinctive substring.
4. **Fix one thing**, recompile, repeat. Resist batching fixes across a long error list; a single
   misplaced `var` can produce a dozen downstream messages.

Most P compile errors are about *where* a declaration sits, not what it says. Before assuming a deep
problem, check: is this `var` at the top of its block? Is this `on` inside a state? Is this `type` at file
scope? Is a single-field tuple missing its trailing comma?

## Checker counterexamples

```bash
.claude/skills/p-verify/scripts/pdock.sh <project-dir> check -tc <tc> -s <N>
```

1. **Find the newest trace.** Runs do not overwrite; they create `BugFinding`, `BugFinding0`,
   `BugFinding2`, …
   ```bash
   DIR=$(ls -dt <project>/PCheckerOutput/BugFinding* | head -1)
   grep -n "ErrorLog" "$DIR"/*_0_0.txt
   ```
2. **Categorize** from the `<ErrorLog>` line and work the most actionable first:

   | Priority | Category | Signature |
   |---|---|---|
   | 1 | unhandled event | `received event ... that cannot be handled` |
   | 2 | null target | `sent to a null machine`, null exception |
   | 3 | assertion failure | `Assertion Failed: file:line:col message` |
   | 4 | deadlock / liveness | `Deadlock detected`, or a monitor left in a `hot` state |

   That order is not arbitrary. A machine killed by an unhandled event stops sending, which shows up later
   as a deadlock or a stuck hot state. Fixing the unhandled event often clears the rest.

3. **Check whether the failure is intended** before fixing anything. In this repo `tcFleetNaive` and
   `tcFleetSanctionFairness` are *expected* to produce counterexamples and the comments above them in
   `PTst/TestScript.p` say so. An intended counterexample is not a regression.

4. **Read the trace backwards** from `<ErrorLog>` to where the invariant first broke — not where it was
   detected.

5. **Apply the per-category procedure** in
   [references/checker-failures.md](references/checker-failures.md).

6. **Verify**: compile → `--replay <seed>` the original counterexample → re-check at `-s 50` →
   re-check at the full count → re-run the *other* test cases. A fix that satisfies one monitor often
   breaks another.

## Rules for fixing

- **Fix the cause, not the symptom.** Adding `ignore eX;` to silence an unhandled event converts a crash
  into a silent wrong answer. The checker stops complaining and the model stops being true.
- **Never weaken an assertion to make a test pass.** If a property really is too strong, narrow it
  deliberately and record why. A spec edited to match a bug is worse than no spec.
- **Do not touch test cases to make a failure go away.** PeasyAI's own fixer prompt says this explicitly:
  the test defines the scenario; changing it changes what you proved.
- **Back up before a multi-file fix and revert the whole set on failure.** Do not leave a half-applied fix
  in the tree.
- **Decide which is wrong — the system or the property.** An assertion failure means they disagree, not
  automatically that the code is broken.

## Reporting

A fix is not done when the error disappears; it is done when you can say what was wrong and show the
result. Carry the schedule count with any "no bug found" claim, and distinguish what you ran from what you
expect. See the evidence discipline in **p-verify**.

## References

| File | Covers |
|---|---|
| [references/compile-errors.md](references/compile-errors.md) | 69 compiler messages → fix |
| [references/checker-failures.md](references/checker-failures.md) | Per-category remediation, liveness procedure, vacuous passes |
| [references/validator-checklist.md](references/validator-checklist.md) | All static-analysis rules as a review checklist, and what they do not cover |
