# P idioms and protocol patterns

Condensed from PeasyAI's `p_documentation_reference.txt`, plus idioms observed in
`Projects/ProjectRobot2026/Common/` and the upstream tutorials.

## Naming conventions

| Kind | Convention | Example |
|---|---|---|
| Types | `t` + PascalCase | `tRequest`, `tWithDrawResp` |
| Events | `e` + PascalCase | `eRequest`, `eTimeOut` |
| Machines | PascalCase | `BankServer`, `Coordinator` |
| Enum type | `t` + PascalCase | `tStatus` |
| Enum values | UPPER_SNAKE | `SUCCESS`, `WITHDRAW_ERROR` |
| Specs | PascalCase, reads as a claim | `BankBalanceIsAlwaysCorrect` |
| States | PascalCase | `Init`, `WaitForRequests` |
| Functions | PascalCase | `HandleRequest` |
| Modules | camelCase | `clientModule` |

## Client-server

The baseline shape. A request carries the sender so the reply has somewhere to go.

```
TestDriver creates BankServer  ->  BankServer creates Database
TestDriver creates Client((serv = server, accountId = id, balance = bal))
Client sends eWithDrawReq((source = this, accountId = ..., amount = ..., rId = ...))
BankServer handles it, queries Database, sends eWithDrawResp to req.source
```

Put `source: machine` (or `client: machine`) in every request payload. Without it the server cannot reply
and the fix later is a change to the type, the sender and the handler.

## Request-response with a blocking receive

A global helper function can wrap a send/receive pair so callers read synchronously:

```p
fun ReadBankBalance(database: Database, accountId: int): int {
  var currentBalance: int;
  send database, eReadQuery, (accountId = accountId,);
  receive {
    case eReadQueryResp: (resp: (accountId: int, balance: int)) {
      currentBalance = resp.balance;
    }
  }
  return currentBalance;
}
```

The machine blocks at the `receive` and defers everything else meanwhile. Convenient, but it removes the
interleavings that would otherwise be explored at that point — so prefer explicit states when the waiting
period is where bugs live.

## Broadcast

```p
var participants: seq[machine];
var i: int;
i = 0;
while (i < sizeof(participants)) {
  send participants[i], ePrepare, (coordinator = this, transId = tid);
  i = i + 1;
}
```

## Quorum / majority

```p
var votes: set[machine];
votes += (sender);                                 // a set, so a duplicate vote cannot double-count
if (sizeof(votes) > sizeof(allNodes) / 2) { goto Committed; }
```

Use a `set` keyed on the voter, not a counter. A retransmitted vote must not count twice, and in a model
with message duplication it will arrive twice.

Compute the majority size once at configuration time: `majoritySize = sizeof(acceptors) / 2 + 1;`.

## Nondeterminism in test drivers

```p
fun HasBeans(): bool { return $; }                 // $ is shorthand for choose()
fun RandomAmount(): int { return choose(100) + 1; }
SetupSystem(choose(3) + 2);                        // 2..4 clients
```

This is how one test case covers a family of scenarios. Keep the ranges small; each `choose` multiplies
the state space.

## Monitor initialization via announce

A monitor often needs initial state the protocol never sends. Announce it from the driver *before* the
system starts generating events:

```p
event eSpec_Init: map[int, int];

// in the test driver, before creating clients
announce eSpec_Init, initBalances;

// in the spec
spec MySafety observes eSpec_Init, eRequest, eResponse {
  var balances: map[int, int];
  start state Init {
    on eSpec_Init goto Active with InitState;
  }
  fun InitState(init: map[int, int]) { balances = init; }
}
```

Order matters: announce first, then create the machines that start sending.

## Timer

```p
machine Timer {
  var target: machine;
  start state WaitForTimerRequests {
    entry (creator: machine) { target = creator; }
    on eStartTimer goto TimerStarted;
    ignore eCancelTimer, eDelayedTimeOut;
  }
  state TimerStarted {
    entry StartTimerEntry;
    defer eStartTimer;
    on eCancelTimer goto WaitForTimerRequests with CancelTimer;
    on eDelayedTimeOut goto WaitForTimerRequests with TimeoutHandler;
  }
}
```

The reusable Timer already exists at `p-source/P/Tutorial/Common/Timer/` — use it rather than
reimplementing. The classic wiring bug is creating it with the *test driver* as `creator`, so `eTimeOut`
goes to the driver instead of the machine that needs it. Pass the machine that will handle the timeout.

## Logical clock instead of a timer

P is untimed. When deadlines matter, model ticks explicitly — the approach in
`Projects/ProjectRobot2026/Common/Clock.p`:

```p
state Ticking {
  entry {
    if (now < maxTicks) { now = now + 1; Broadcast(now); send this, eContinue; }
    else { Broadcast(FAR_FUTURE()); goto Stopped; }
  }
  on eContinue goto Ticking;
}
state Stopped { ignore eContinue; }
```

The final `FAR_FUTURE()` tick closes every open obligation, which keeps liveness checks meaningful in a
bounded run. `send this, eContinue;` yields so other machines interleave.

## Failure injection

```p
machine FailureInjector {
  var nodes: seq[machine];
  start state InjectFailures {
    entry { send nodes[choose(sizeof(nodes))], halt; }
  }
}
```

`halt` terminates the target. The reusable version is at
`p-source/P/Tutorial/Common/FailureInjector/`. Within a machine, terminate yourself with `raise halt;`.

## System-assembly machine

Rather than wiring everything in the test driver, give the system one assembly machine and let drivers be
one-liners:

```p
machine FleetSystem {
  start state Init {
    entry (twoPhase: bool) {
      // new every guard, coordinator, manager, robot, clock in dependency order
      // then seed the initial tasks
    }
  }
}

machine TestFleetTwoPhase { start state Init { entry { new FleetSystem(true); } } }
```

Two drivers differing only by a config flag then give two test cases over identical system code.

## Constants

P has no `const`:

```p
fun MAX_RETRIES(): int { return 3; }
fun FAR_FUTURE(): int { return 1000000; }
```

## Protocol sketches

**Two-phase commit.** Coordinator broadcasts `ePrepare`; participants reply `eVoteYes`/`eVoteNo`; all yes
→ `eGlobalCommit`, any no → `eGlobalAbort`. Safety: atomicity — all commit or all abort.

**Paxos.** Proposer sends `ePrepare(ballot)` to acceptors; acceptors reply `ePromise`/`eReject`; on a
majority of promises the proposer sends `eAccept(ballot, value)`; acceptors reply `eAccepted`; on a
majority the value is chosen and learners are notified. Safety: at most one value is ever chosen.

**Raft.** Leader election by randomized timeout; leader sends `eAppendEntries` heartbeats; followers reply;
an entry commits once a majority has replicated it. Safety: one leader per term, plus log matching.

**Ring leader election.** Each node knows its successor and circulates its id; forward higher ids, drop
lower; the node that receives its own id is leader.

Worked implementations of all four are in the corpus — see
`p-project/references/examples-index.md`.
