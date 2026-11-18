# P test cases and the module system

Condensed from PeasyAI's `p_test_cases_guide.txt` and `p_module_system_guide.txt`, cross-checked against
both styles in use here: `Projects/ProjectRobot2026/MobileRobots/PTst/TestScript.p` and
`p-source/P/Tutorial/1_ClientServer/PTst/Testscript.p`.

## What a test case is

```
test <tcName> [main=<MachineName>] : <modExpr> ;
```

A test case names a closed system plus the monitors to check over it. `p check -tc <tcName>` explores
executions of that system. `[main=...]` names the machine the checker creates first; omit it and the
checker picks one.

For every test case, PChecker always checks four things, whether or not you declare a monitor:

1. no unhandled events,
2. every local `assert` holds,
3. no deadlock,
4. every monitor attached to the module is satisfied — safety never violated, liveness never stuck in a
   `hot` state at the end of an execution.

So a test with no monitors is still worth running: it finds unhandled events and deadlocks.

## Two styles, both valid

### Explicit machine set — what this repo uses

```p
test tcFleetTwoPhase [main=TestFleetTwoPhase]:
  assert RegimentationSafety, NoStaleAdmission, NoDoubleOutcome,
         EveryObligationResolved, AdaptationCompletes, AdaptationTerminates,
         LockoutBeforeEntry in
  { TestFleetTwoPhase, FleetSystem, Robot, ResourceGuard,
    AdaptationCoordinator, ObligationManager, Clock, HumanRequester };
```

Every machine is listed in braces. No `module` declarations needed. Simple, and obvious about what is in
scope — at the cost of repeating the list in each test.

### Module unions — what the upstream tutorials use

```p
module Client = { Client };
module Bank   = { BankServer, Database };

test tcSingleClient [main=TestWithSingleClient]:
  assert BankBalanceIsAlwaysCorrect, GuaranteedWithDrawProgress in
  (union Client, Bank, { TestWithSingleClient });
```

Better when you want to swap a component for an abstraction, or test subsystems separately.

Note the trailing `;` in both: a `test` declaration ends with a semicolon even though it closes with `}`
or `)`. That is the one place `};` is correct.

## Module expressions

```p
{ A, B }                          // primitive: a set of machines
{ AbstractServer -> Server }      // bind a machine to an interface name
union modA, modB, { Driver }      // compose
assert Spec1, Spec2 in modExpr    // attach monitors
module name = modExpr;            // name it for reuse
```

A test module must be a **closed system**: every machine that gets created must be defined in the union.
A `new` of a machine outside the module is a compile error, and forgetting the test driver itself in the
union is the usual way to hit it.

## Monitors are opt-in per test

A monitor not named in a test's `assert ... in` list **does not run in that test**. It is dead code there.
A test that passes while checking nothing is the most expensive kind of false confidence, so when adding a
monitor, add it to the tests that should enforce it.

The reverse also holds: a monitor that does not `observe` an event it needs fails to compile rather than
failing silently.

## File organization

Both styles split PTst into:

- **Driver machines** — the environment: they create the system and generate inputs.
- **Test declarations** — the `test ... ;` lines.

They may live in one file or two (`TestDriver.p` + `TestScript.p`). The static checker warns when a PTst
file has machines but no `test` declaration; for a deliberate two-file split that warning is expected
noise.

**Never declare the same event in both the driver and the script file.** Duplicate declarations are a
compile error.

## Driver machines

Keep them minimal. The idiomatic form here is a driver whose entire job is to create the system machine:

```p
machine TestFleetTwoPhase {
  start state Init { entry { new FleetSystem(true); } }
}

machine TestFleetNaive {
  start state Init { entry { new FleetSystem(false); } }
}
```

Two drivers differing only in a config flag give two test cases over the same code. Use `choose()` inside
a driver to let the checker explore a range of configurations:

```p
start state Init { entry { SetupClientServerSystem(choose(3) + 2); } }   // 2..4 clients
```

The parameterized form declares several tests at once:

```p
test param (nClients in [2, 3, 4]) tcMultiClient [main=TestDriver]: ... ;
```

## Stating the expected outcome

This repo's convention, worth keeping: a comment above each test saying what is expected, explicitly
labelled as a hypothesis until it has been run.

```p
// Expected (hypothesis): counterexample. Zone 1's controller admits a robot
// after the closure was committed.
test tcFleetNaive [main=TestFleetNaive]: ... ;
```

A test whose failure is *intended* must say so, or the next reader files it as a regression. See
**p-verify** for the evidence discipline this supports.
