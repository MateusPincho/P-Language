---
name: p-project
description: Scaffold a new P project or build a complete P model from a design document. Use when asked to create a P project, turn a design doc or system description into P code, generate machines, specs or test drivers, or add a machine to an existing P solution.
---

# Building P projects

Generating a whole P project in one pass does not work. The dependency order matters: every machine
references the types and events, every test references the machines' constructor signatures, and a wrong
name early cascades through everything after it. Build it in stages, validating each file as it is
written.

Related: **p-language** for syntax, **p-verify** to compile and check, **p-debug** when something fails.

## Stages

### 1. Design document

Get one, or write one, against the six-section contract in
[references/design-doc-template.md](references/design-doc-template.md): Title, Introduction with
assumptions, Components (source vs test, with states, local state and initialization in plain English),
Interactions (source/target/payload/description/effects per event), Specifications (safety and liveness,
split explicitly), Test Scenarios.

The quality of everything downstream is set here. Two sections carry most of the weight:

- **Initialization**, per machine, in plain English — this decides Pattern A vs Pattern B and therefore
  how the test driver wires the system.
- **Specifications**, stated precisely and naming the relevant events — this is what the monitors check,
  and a vague property produces a monitor that passes without proving anything.

If the request is a one-line system description, write the design doc first and show it. Do not invent
requirements silently: ask when a choice would materially change the model (failure model, message
reliability, how many of each machine).

### 2. Scaffold

```bash
PROJ=<path>/<Name>
mkdir -p "$PROJ"/{PSrc,PSpec,PTst}
sed 's/{project_name}/<Name>/g' .claude/skills/p-project/assets/pproj-template.xml > "$PROJ/<Name>.pproj"
```

`PGenerated/` is created by the compiler; it does not need to exist. Layout rules and the shared-`Common/`
variant used by `Projects/ProjectRobot2026` are in
[references/project-layout.md](references/project-layout.md).

### 3. Machine list, then file list

Name the machines from the design doc's Components section, splitting source machines (`PSrc/`) from test
machines (`PTst/`). Then the files: one `.p` per machine, plus `Enums_Types_Events.p`.

### 4. `PSrc/Enums_Types_Events.p` — always first

Every other file references these names, so an error here cascades. Declare enums, then types, then
events.

- Payload types before the events that use them. `type tReq = (...); event eReq: tReq;`
- Name a machine's config type `t<MachineName>Config`.
- Field names descriptive and unambiguous — these are the contract for every `send` site.
- Only declare a config *event* if the design actually uses Pattern B. Do not invent `eXInit` events
  nobody sends.

### 5. Each machine, in two passes

Pass one: the structure — variables, states with `start`/`hot`/`cold`, entry/exit, `on ... do`/
`on ... goto`, `defer`, `ignore`, and function signatures with **empty bodies and a comment** saying what
each will do.

Pass two: fill in the bodies without changing the structure.

The split exists because single-pass generation reliably produces machines whose states do not cover
their reachable events. Deciding the state/event matrix first, with nothing else to think about, is what
prevents the most common checker bug. While writing the structure, go state by state and ask which events
can arrive — then handle, `defer`, or `ignore` each one.

Per-stage rules are in [references/generation-stages.md](references/generation-stages.md).

### 6. Specs in `PSpec/`

One `spec` per property from the design doc. Derive the `observes` list from what the property needs to
know, not from what looks related. See `p-language/references/specs-monitors.md`.

### 7. Test drivers in `PTst/`

One driver machine per Test Scenario, plus the matching `test tc... [main=...]: assert ... in { ... };`
declaration. Read each machine's start-state entry signature to get the `new` payloads right.

Then review the wiring against
[references/wiring-review.md](references/wiring-review.md) — dependency order, circular dependencies,
empty collections, named-tuple construction. These are semantic errors no static check catches and the
most common reason a generated project compiles but deadlocks.

### 8. Validate as you go

After writing each file, before moving to the next:

```bash
python3 -I .claude/skills/p-language/scripts/validate_p.py "$PROJ/PSrc/File.p" --project "$PROJ"
```

Not a batch at the end. A wrong field name in `Enums_Types_Events.p` is cheap to fix immediately and
expensive once six machines reference it.

### 9. Compile, then check

Hand off to **p-verify**. Expect to iterate; a first-pass model that compiles clean is unusual.

## Adding to an existing project

Same stages, narrowed:

1. Read the existing `Enums_Types_Events.p` and the `.pproj`'s `InputFiles`.
2. Add any new types and events there — never in the new machine's file, and never duplicating an
   existing declaration.
3. Write the machine in two passes.
4. Check whether existing machines need handlers for its new events.
5. Add it to the test module in every test case that should include it. A machine created but absent from
   the module is a "test module is not closed" compile error.
6. Validate, compile, check.

Adding a `.p` file to a folder the `.pproj` already lists needs no `.pproj` edit; `<PFile>` entries are
directories. A new folder does.

## Honesty about generated models

Generated P code is a draft until the toolchain agrees. Do not describe a model as working, correct, or
verified before `p compile` and `p check` have run — and when they have, carry the schedule count. See
the evidence discipline in **p-verify**; in this repo these files double as a graded verification record.

## References

| File | Covers |
|---|---|
| [references/design-doc-template.md](references/design-doc-template.md) | The six-section contract, with the template |
| [references/project-layout.md](references/project-layout.md) | Folder rules, `.pproj` format, both layouts in use here |
| [references/generation-stages.md](references/generation-stages.md) | Per-stage rules for types/events, machines, specs, tests |
| [references/wiring-review.md](references/wiring-review.md) | Dependency order, circular deps, init events, config checks |
| [references/examples-index.md](references/examples-index.md) | Where to find a worked example of a given pattern |
