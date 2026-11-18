# P-Language

Work with the [P language](https://p-org.github.io/P/) — modeling and formal verification of distributed systems.

## Contents

| Folder | Description |
| --- | --- |
| [`P-Tutorial/`](P-Tutorial/) | A tutorial from zero: installation, a first program (client-server), specs, and running the checker. |
| [`Projects/ProjectManufacturingCell2026/`](Projects/ProjectManufacturingCell2026/) | Graduate project: verified regulation management for a manufacturing cell (P model + PObserve). [Assignment](Projects/ProjectManufacturingCell2026/ASSIGNMENT.md). |
| [`Projects/ProjectRobot2026/`](Projects/ProjectRobot2026/) | Graduate project: verified regulation management for a mobile robot fleet (P model + PObserve). [Assignment](Projects/ProjectRobot2026/ASSIGNMENT.md). |

## Prerequisites

- .NET SDK **8.0**
- Java 11+
- The P tool: `dotnet tool install --global P`

Full install instructions in [`P-Tutorial/README.md`](P-Tutorial/README.md).

## Building and checking

Each folder compiles independently — `cd` into it first:

```powershell
cd P-Tutorial
p compile
p check -tc tcSingleClient -i 100
```

## Containerized toolchain (Docker)

The whole toolchain (.NET 8, Java, the P tool, and the
[PeasyAI](https://p-org.github.io/P/peasyai/) MCP server) lives in one image, so nothing
needs installing on the host. `.env` is machine-specific and gitignored — create it once:

```bash
cat > .env <<'ENV'
UID=1000
GID=1000
PROJECT_MOUNT=/absolute/path/to/this/repo
PEASYAI_CONFIG_DIR=/home/you/.peasyai
PEASYAI_VERSION=1.0.0
ENV
docker compose build
```

`PROJECT_MOUNT` must be the repo's absolute path on the host: the repo is bind-mounted at
that same path inside the container, so absolute paths mean the same thing on both sides.

```bash
docker compose run --rm p bash          # interactive shell with p on PATH
cd Projects/ProjectRobot2026/MobileRobots && p compile
```

### PeasyAI (MCP)

`tools/peasyai-mcp.sh` runs the MCP server in that container over stdio; register it with
`claude mcp add peasyai -- /absolute/path/to/this/repo/tools/peasyai-mcp.sh`. It builds the
image on first use. LLM credentials go in `$PEASYAI_CONFIG_DIR/settings.json` (generate it
with `docker compose run --rm p peasyai-mcp init`) and are mounted in, never baked into the
image. PeasyAI calls its own configured LLM provider, billed separately.
