# Per-stage generation rules

Distilled from PeasyAI's `generate_enums_types_events.txt`, `generate_machine_structure.txt`,
`generate_machine.txt`, `generate_spec_files.txt` and `generate_test_files.txt`, with the prompt
scaffolding removed.

---

## Stage 1 — `PSrc/Enums_Types_Events.p`

Everything else references these names. Decisions here are expensive to change later, because a field
name is the API contract for every construction site in the project.

Order within the file: enums, then types, then events. A payload type must be declared before the event
that uses it.

### Rules

1. **No trailing commas in type definitions**, even single-field:
   ```p
   type tLearnPayload   = (learnedValue: int);               // correct
   type tAcceptorConfig = (learners: seq[machine]);           // correct
   ```
   The trailing comma belongs to single-field *values* — `(learnedValue = 7,)` — never to a type.

2. **Descriptive, unambiguous field names.** They appear at every send site and every field access.
   ```p
   (proposalNumber: int, acceptedValue: int)    // good
   (value: int)                                 // bad: ambiguous across types
   ```

3. **Config types named `t<MachineName>Config`**, matching that machine's dependencies exactly:
   ```p
   type tProposerConfig = (acceptors: seq[machine], learners: seq[machine], proposerId: int);
   type tAcceptorConfig = (learners: seq[machine]);
   type tLearnerConfig  = (majoritySize: int);
   ```

4. **Do not declare config init events** (`eProposerInit`, `eAcceptorInit`) unless the design actually
   uses Pattern B. Most machines take config through `new Machine(config)`. An unused init event is
   noise that invites a wiring mistake.

5. **Field names become the construction contract.** Given `type tNodeConfig = (failureDetector: machine);`
   ```p
   new Node((failureDetector = fd,));     // correct
   new Node((fd,));                       // wrong: anonymous tuple
   new Node(fd);                          // wrong: bare value
   ```

6. **Event payload types define the send-site contract.** Given
   `event eNodeSuspected: tNodeSuspectedPayload;` with `type tNodeSuspectedPayload = (suspectedNode: machine);`
   ```p
   send client, eNodeSuspected, (suspectedNode = node,);   // correct
   send client, eNodeSuspected, (node);                     // wrong
   ```

7. **Declare each thing exactly once** across the whole project. Enum values are global constants and
   must be unique program-wide.

8. Put `source: machine` (or `client: machine`) in every request payload, or the receiver cannot reply.

---

## Stage 2 — machine structure

Emit the skeleton only: variables, states, handlers, function signatures with **empty bodies plus a
comment** describing what each will do.

Include:

1. Machine declaration with local variable declarations.
2. Every state, with its `start` / `hot` / `cold` annotation.
3. `entry` and `exit` references.
4. Event handlers: `on ... do` and `on ... goto`.
5. `defer` and `ignore`.
6. Function declarations with parameters and return types, bodies empty.

Must **not** contain: a `spec`, a `test`, a `module`, an `assert`, an `observes` clause, or any event,
type or enum declaration. Those live elsewhere.

### The point of this stage

Decide the state/event matrix with nothing else competing for attention. For **every** state, work
through which events can arrive — including events still queued from an earlier state — and choose one of
`on` / `defer` / `ignore` for each. PChecker reports an unhandled event as a bug, and this is the most
common defect in generated P.

Think especially about staleness: a machine that moves from `PhaseA` to `PhaseB` can still have `PhaseA`
events in its queue. Those need `ignore` in `PhaseB`.

### Configuration

Pick Pattern A (constructor payload) or Pattern B (init event) per machine and stay consistent. Full
treatment in `p-language/references/machines.md`. A machine with no external dependencies takes no entry
parameter.

---

## Stage 3 — machine bodies

Fill in the bodies. **Do not change the structure** — not the variables, not the states, not the
handlers, not the signatures. If a body cannot be written without a structural change, that is a signal
to revisit stage 2 deliberately, not to edit silently.

### Rules

1. Never `=` in a declaration. `var name: type;` then `name = value;`.
2. P initializes variables to their defaults, so explicit initialization is often unnecessary.
3. **The start-state entry must unpack every field of the config payload** into a local variable, and
   compute derived values: `majoritySize = sizeof(acceptors) / 2 + 1;`. A Pattern B config handler does
   the same, then `goto`es the first operational state.
4. **Use the exact type and field names from `Enums_Types_Events.p`.** Do not invent alternatives.
   ```p
   // Given: type tPromisePayload = (proposer: machine, highestProposalSeen: int, acceptedValue: int);
   fun HandlePromise(msg: tPromisePayload) { ... msg.highestProposalSeen ... }   // correct
   fun HandlePromise(msg: tPromise)        { ... msg.propNum ... }               // wrong on both counts
   ```
5. Named tuples include **all** fields. Single-field values take the trailing comma; type annotations do
   not.
6. Every `send` target is a machine-typed variable that has actually been assigned — never `null` or a
   `default`.
7. File-scope helper functions, if the design specifies them, go after the machine's closing brace:
   ```p
   fun CreateTimer(client: machine): Timer { return new Timer(client); }
   fun StartTimer(timer: Timer) { send timer, eStartTimer; }
   ```

### Checklist

- [ ] Every state handles, defers or ignores every event this machine can receive.
- [ ] Start-state entry unpacks the whole constructor payload.
- [ ] Derived values computed at init.
- [ ] All `send` targets are assigned machine variables.
- [ ] No event, type or enum declared in this file.
- [ ] Single-field tuple *values* have trailing commas; annotations do not.
- [ ] Type and field names match `Enums_Types_Events.p` exactly.

---

## Stage 4 — specs

One `spec` per property in the design doc's Specifications section.

1. `spec Name observes eA, eB { ... }`.
2. Forbidden in a monitor: `this`, `new`, `send`, `announce`, `receive`, `$`, `$$`, `pop`.
3. For per-machine state use `map[machine, T]`, keyed from an event payload — there is no `this`.
4. **Every monitor needs at least one `assert`**, or a `hot` state for liveness. Otherwise it passes
   vacuously.
5. No empty or placeholder functions.
6. Observe only events that exist. An event handled in the body must be in `observes` — that is a compile
   error, not a silent no-op.
7. `entry` functions in a spec take no parameters.

Deriving `observes` is the part that matters and no tool checks it. See
`references/wiring-review.md` and `p-language/references/specs-monitors.md`.

---

## Stage 5 — tests

One driver machine per Test Scenario, plus the matching `test` declaration **in the same file**.

1. Read each machine's start-state entry signature to build the right `new` payload. Guessing produces a
   type error at best and a null reference at worst.
2. Create machines in dependency order.
3. Break circular dependencies with an init event.
4. Never pass an empty or `default()` collection as config.
5. Keep drivers minimal — ideally `new SystemMachine(cfg);` and nothing else.
6. Each `test` lists the monitors it should enforce: `assert Spec1, Spec2 in { ... };`. A monitor not
   listed does not run.
7. The module must be closed: every machine created appears in it, including the driver.
8. Never declare the same event in both the driver and the script file.
9. Add a comment stating the expected outcome, labelled as a hypothesis until it has been run.

Then review against `references/wiring-review.md`. Wiring errors are semantic; they compile fine and fail
at check time.
