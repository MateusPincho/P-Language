# P project layout

## Folders

| Folder | Holds | Never holds |
|---|---|---|
| `PSrc/` | `Enums_Types_Events.p`, one `.p` per machine, `Modules.p` if you use modules | specs, test drivers, test declarations |
| `PSpec/` | `spec` monitors | machines, tests |
| `PTst/` | driver machines and `test ... ;` declarations | protocol machines |
| `PGenerated/` | compiler output | anything hand-written |

`PGenerated/` and `PCheckerOutput/` are gitignored, regenerated on every run, and must never be
hand-edited or committed. The compiler creates `PGenerated/`, so scaffolding need not.

Conventions worth keeping: one `.p` per machine or per tight logical group; `Enums_Types_Events.p` holds
every type, enum and event for the project, declared exactly once.

## The `.pproj`

```xml
<!-- P Project file for KVStore -->
<Project>
<ProjectName>KVStore</ProjectName>
<InputFiles>
	<PFile>./PSrc/</PFile>
	<PFile>./PSpec/</PFile>
	<PFile>./PTst/</PFile>
</InputFiles>
<OutputDir>./PGenerated/</OutputDir>
</Project>
```

Template: `.claude/skills/p-project/assets/pproj-template.xml`, with `{project_name}` to substitute.

**`<PFile>` entries are directories with trailing slashes**, not individual files. So adding a `.p` file
to a folder already listed needs no `.pproj` edit — a new *folder* does. A "could not find event" error
for an event you can see declared usually means its folder is not in `<InputFiles>`.

`p` finds the `.pproj` by searching the current directory, so always `cd` into the directory that holds it
before compiling.

## Two layouts in use here

### Standalone

What the upstream tutorials and PeasyAI produce. Everything under one root:

```
KVStore/
├── KVStore.pproj
├── PSrc/{Enums_Types_Events.p, KVStore.p, Client.p}
├── PSpec/KVStoreSpec.p
└── PTst/TestScript.p
```

Use this for a new, self-contained project.

### Shared `Common/`

What `Projects/ProjectRobot2026` does, so two sibling projects can share machines and specs:

```
ProjectRobot2026/
├── Common/                        <- shared; sibling of the project root, not inside it
│   ├── Types.p                    types + events
│   ├── MonitorEvents.p            monitor vocabulary, shared with PObserve
│   ├── Clock.p  ResourceGuard.p  AdaptationCoordinator.p
│   ├── ObligationManager.p  HumanRequester.p
│   ├── Specs.p                    design-time specs
│   └── RuntimeSpecs.p             run-time specs, for PObserve
└── MobileRobots/                  <- cd HERE to run p
    ├── MobileRobots.pproj
    ├── PSrc/Robot.p               wiring and topology only
    ├── PSpec/FleetSpecs.p         project-specific monitors
    └── PTst/TestScript.p
```

The `.pproj` sits one level down and reaches up:

```xml
<Project>
  <ProjectName>MobileRobots</ProjectName>
  <InputFiles>
    <PFile>../Common/</PFile>
    <PFile>./PSrc/</PFile>
    <PFile>./PSpec/</PFile>
    <PFile>./PTst/</PFile>
  </InputFiles>
  <OutputDir>./PGenerated/</OutputDir>
</Project>
```

Two consequences:

- `p` runs from `MobileRobots/`, not from `ProjectRobot2026/`. A stray `PGenerated/` at the
  `ProjectRobot2026/` level is the signature of compiling one level too high.
- For cross-file static analysis, point `--project` at `ProjectRobot2026/` — the directory *above* the
  `.pproj` — so `../Common/*.p` is in scope. The tool walks up to the nearest `.pproj` by default, which
  would miss `Common/`:

```bash
python3 -I .claude/skills/p-language/scripts/validate_p.py \
  Projects/ProjectRobot2026/Common/Clock.p --project Projects/ProjectRobot2026
```

## Naming

| Kind | Convention | Example |
|---|---|---|
| Types | `t` + PascalCase | `tRequest` |
| Events | `e` + PascalCase | `eRequest` |
| Machines, specs, states, functions | PascalCase | `BankServer`, `GuaranteedProgress`, `Init` |
| Enum values | UPPER_SNAKE | `WITHDRAW_SUCCESS` |
| Modules | camelCase | `clientModule` |

Filename casing is not enforced and is inconsistent across the corpus — `TestScript.p` here,
`Testscript.p` upstream. Match whatever the project already uses.
