# Where to find a worked example

**These paths are optional deep lookups.** They live in `p-source/`, an untracked clone of the upstream P
repo that may not be present. Everything needed to write correct P is in the skills themselves; this file
only saves you from reinventing a pattern someone already wrote.

Check availability first:

```bash
ls p-source/P/Tutorial/ 2>/dev/null || echo "p-source/ not present - skip this file"
```

This replaces PeasyAI's three RAG tools (`search-examples`, `get-context`, `index-examples`). Grep over
the corpus beats a local vector store, needs no embedding model, and shows you the real file.

```bash
grep -rln "hot state" --include=*.p p-source/P/Tutorial/            # liveness monitors
grep -rln "receive {" --include=*.p p-source/P/Tutorial/            # blocking receive
grep -rn  "test param" --include=*.p p-source/P/Tutorial/           # parameterized tests
```

## By pattern

| Looking for | Read |
|---|---|
| **Machine wiring done right** — the four checks in `wiring-review.md`, purpose-built to show them | `p-source/P/Src/PeasyAI/resources/rag_examples/BestPractices_MachineWiring/` (`PSrc/Types_Events.p`, `Coordinator.p`, `Worker.p`, `PTst/TestDriver.p` — 8KB total, the single best thing to read first) |
| The smallest complete project: machines, spec, test, modules | `p-source/P/Tutorial/1_ClientServer/` |
| Blocking `receive`, request-response helpers | `p-source/P/Tutorial/1_ClientServer/PSrc/Server.p` |
| Safety and liveness monitors side by side | `p-source/P/Tutorial/1_ClientServer/PSpec/BankBalanceCorrect.p` |
| Module unions, abstract component substitution | `p-source/P/Tutorial/1_ClientServer/PSrc/ClientServerModules.p` |
| Parameterized tests (`test param (n in [2,3,4])`) | `p-source/P/Tutorial/1_ClientServer/PTst/Testscript.p` |
| Two-phase commit, failure injection | `p-source/P/Tutorial/2_TwoPhaseCommit/` |
| Nondeterministic environment modeling with `$` and `choose` | `p-source/P/Tutorial/3_EspressoMachine/` |
| Failure detection, timers, heartbeats | `p-source/P/Tutorial/4_FailureDetector/` |
| Paxos consensus | `p-source/P/Tutorial/5_Paxos/`, `p-source/P/Tutorial/BasicPaxos/` |
| Raft: the largest worked model in the corpus | `p-source/P/Tutorial/6_Raft/` (`PSrc/Server.p` is 36KB — skim, don't read whole) |
| Reusable `Timer` — use it, do not reimplement | `p-source/P/Tutorial/Common/Timer/` |
| Reusable `FailureInjector` | `p-source/P/Tutorial/Common/FailureInjector/` |
| Shared-memory abstractions | `p-source/P/Tutorial/Common/SharedMemory/` |

## Advanced / verification-oriented

`p-source/P/Tutorial/Advanced/` has eight projects aimed at verification rather than tutorial clarity:
`1_ChainReplicationVerification`, `2_TwoPhaseCommitVerification`, `3_RingLeaderVerification`, `4_Paxos`,
`5_Consensus`, `6_DistributedLock`, `7_ShardedKV`, `8_LockServer`. Worth reading for how specs are written
when proving something is the goal.

## Single-file models

`p-source/P/Src/PeasyAI/resources/rag_examples/` holds 83 `.p` files across 22 projects, several as a
single `PSrc/System.p` — compact enough to read whole: `Portfolio_BenOr`, `Portfolio_ChangRoberts`,
`Portfolio_DAO`, `Portfolio_German`, `Portfolio_Streamlet`, `Portfolio_TokenRing`, plus
`Advanced_*` mirrors of the tutorials above.

## Design documents

`p-source/P/Src/PeasyAI/resources/system_design_docs/` — ten docs in the exact format the generation
pipeline consumes, plus `DESIGN_DOC_TEMPLATE.md`: Basic Paxos, Client Server, Distributed Lock Server,
Espresso Machine, Failure Detector, Hotel Management, Raft Leader Election, Simple Message Broker, Two
Phase Commit.

Useful as fixtures: several have a matching worked project in `rag_examples/`, so you can generate from
the doc and compare against a known-good result.

## Benchmark suite

`p-source/P/Src/PeasyAI/resources/p-model-benchmark/` — a graded eval suite in tiers, each a prompt or
design doc paired with a reference answer. `8_dd2psrcA/LightSwitch/` and `9_dd2psrcB/TwoPhaseCommit/`
include a design doc plus the expected full project, which makes them the best end-to-end test of this
skill set.

## In this repo

The ground truth for conventions, since these are the files you are actually working on:

| For | Read |
|---|---|
| Idiomatic machine, doc-comment style, logical clock | `Projects/ProjectRobot2026/Common/Clock.p` |
| Types and events grouped by concern | `Projects/ProjectRobot2026/Common/Types.p` |
| Design-time specs, safety and liveness | `Projects/ProjectRobot2026/Common/Specs.p` |
| Run-time specs as bounded-response safety, for PObserve | `Projects/ProjectRobot2026/Common/RuntimeSpecs.p` |
| System-assembly machine and topology wiring | `Projects/ProjectRobot2026/MobileRobots/PSrc/Robot.p` (`FleetSystem`) |
| Test style: minimal drivers, explicit machine sets, expected-outcome comments | `Projects/ProjectRobot2026/MobileRobots/PTst/TestScript.p` |
| A monitor with an explicitly scoped claim | `Projects/ProjectRobot2026/MobileRobots/PSpec/FleetSpecs.p` |

Prefer these over the upstream tutorials when the question is "how should it look *here*" — the shared
`Common/` layout and the explicit `assert ... in { ... }` test style differ from upstream.
