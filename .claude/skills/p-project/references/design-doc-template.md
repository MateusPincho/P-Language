# P design document contract

A P design document is the input to the whole generation pipeline. Six sections, in this order. From
PeasyAI's `generate_design_doc.txt` and `system_design_docs/DESIGN_DOC_TEMPLATE.md`.

Two sections carry most of the weight:

- **Initialization**, per machine, in plain English. It decides Pattern A vs Pattern B and therefore how
  the test driver wires the system. Vague here means a wiring bug later.
- **Specifications**, stated precisely and naming the relevant events. A vague property produces a
  monitor that passes without proving anything.

Worked examples live in `p-source/P/Src/PeasyAI/resources/system_design_docs/` — ten of them, including
Basic Paxos, Two Phase Commit, Raft Leader Election, Failure Detector, Distributed Lock Server and
Espresso Machine. Read one before writing a new doc.

## Template

```markdown
# [System Name]

## Introduction

[One paragraph overview: what the system does, what problem it solves, and the core protocol or algorithm it implements.]

**Assumptions:**
1. [Assumption about communication model, e.g., reliable message delivery, no Byzantine faults]
2. [Assumption about failure model, e.g., crash-stop failures, no network partitions]
3. [Assumption about concurrency, e.g., requests are serialized, at most N concurrent clients]
4. [Assumption about reusable modules, e.g., "The Timer machine is a pre-existing reusable module — do NOT re-implement it. Use CreateTimer(this), StartTimer(timer), and CancelTimer(timer)."]

## Components

<!--
  Split into Source Components (protocol machines → PSrc/) and
  Test Components (test-only machines like clients/drivers → PTst/).
-->

### Source Components

#### 1. [MachineName]
- **Role:** [One-sentence role description.]
- **States:** [List known states, e.g., Init, WaitingForPrepare, Committed, Aborted]
- **Local state:**
    - `[variableName]`: [what it tracks]
    - `[variableName]`: [what it tracks]
- **Initialization:** [Describe in plain English what information this machine needs to start and how it receives it, e.g., "Created with a reference to all acceptors, all learners, and a unique proposer ID." or "Waits for a configuration event from the coordinator before becoming operational."]
- **Behavior:**
    - [Key behavior point, e.g., "Sends prepare requests to all participants and waits for responses."]
    - [Key behavior point, e.g., "Times out and aborts if responses are not received in time."]
- **Event handling notes:**
    - In [StateName]: ignore `[eStaleEvent1]`, `[eStaleEvent2]`
    - In [StateName]: defer `[eDeferredEvent1]`, `[eDeferredEvent2]`

#### 2. [MachineName]
- ...

### Test Components

#### 3. [ClientOrDriverName]
- **Role:** [One-sentence role description.]
- **States:** [List known states]
- **Local state:**
    - `[variableName]`: [what it tracks]
- **Initialization:** [Describe what information this machine needs to start, e.g., "Created with a reference to the server and the number of requests to send."]
- **Behavior:**
    - [Key behavior point, e.g., "Issues N write transactions with random key/value using choose()."]
    - [Key behavior point, e.g., "On success, performs a read and asserts the value matches."]

## Interactions

1. **[eEventName]**
    - **Source:** [MachineName]
    - **Target:** [MachineName(s)]
    - **Payload:** [Describe the data carried by this event in plain English, e.g., "the proposer's reference, the proposal number, and the proposed value"]
    - **Description:** [What this event represents and when it is sent.]
    - **Effects:**
        - [Effect on the receiver, including state transitions.]
        - [Any conditional behavior, e.g., "If the proposal number is higher than any previously seen..."]

2. **[eEventName]**
    - **Source:** [MachineName]
    - **Target:** [MachineName(s)]
    - **Payload:** none
    - **Description:** [What this event represents.]
    - **Effects:**
        - [Effect on the receiver.]

## Specifications

<!--
  Each property should have a descriptive name, its type (safety/liveness),
  and a precise English statement. Reference the relevant events naturally
  within the description so the LLM knows which events to observe.
-->

1. **[PropertyName]** (safety property):
   [Precise statement that naturally references the relevant events. E.g., "Whenever an eAccepted is sent for a value, no future eAccepted may carry a different value — only one value can ever be chosen."]

2. **[PropertyName]** (liveness property):
   [Precise statement that naturally references the relevant events. E.g., "If a majority of participants are alive, an eLearn event carrying the consensus value is eventually delivered."]

## Test Scenarios

<!--
  Concrete test scenarios with specific machine counts and expected behavior.
  Each scenario maps to a test case in PTst/.
-->

1. [N] [machine_type_1], [M] [machine_type_2], [K] [machine_type_3] — [description of what is being tested and expected outcome].
2. [N] [machine_type_1], [M] [machine_type_2] — [description of failure scenario, e.g., "one proposer fails mid-protocol, remaining machines still reach consensus"].
3. [Description of edge case or stress scenario].
```

## Notes on each section

**Introduction.** One paragraph plus explicit assumptions. The assumptions decide what the model must
represent: a crash-stop failure model needs a failure injector, reliable delivery means no retry logic.
Call out reusable modules here too — the `Timer` at `p-source/P/Tutorial/Common/Timer/` already exists
and should not be reimplemented.

**Components.** Split source machines (`PSrc/`) from test machines (`PTst/`). Per machine: role, states,
local state with what each variable tracks, initialization, behavior, and event-handling notes naming
which events each state should `ignore` or `defer`. Those notes are what stage 2 of generation turns into
the state/event matrix, and they are the difference between a model that passes the checker and one that
dies on an unhandled event.

**Interactions.** One entry per event: source, target, payload in plain English, description, and
effects on the receiver including state transitions. The payload descriptions become the types in
`Enums_Types_Events.p`, so name the data precisely. Every request needs a sender reference in its payload
or the receiver cannot reply.

**Specifications.** Each property gets a name, a type (safety or liveness), and a precise statement that
names the relevant events — that is how the monitor's `observes` list gets derived. Split safety from
liveness explicitly; they are built differently (`assert` vs `hot` states).

Write properties as claims that could be false. "The system works correctly" produces nothing. "Whenever
an eAccepted is sent for a value, no future eAccepted may carry a different value" produces a monitor.

**Test Scenarios.** Concrete machine counts and expected outcomes. Each maps to one test case in `PTst/`.
Include at least one failure scenario. If a scenario is expected to produce a counterexample, say so —
that becomes the comment above the test declaration, and it is what stops a future reader filing an
intended counterexample as a regression.
