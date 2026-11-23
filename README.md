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

The whole toolchain (.NET 8, Java and the P tool) lives in one image, so nothing needs installing on
the host. Build it once, from the repo root:

```bash
docker compose build
```

The container user gets uid/gid 1000, so the files it writes into the repo are owned by you. If your
ids differ, build with `HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose build`.

The repo is mounted at `/workspace` inside the container, and a shell starts there, so use paths
relative to the repo root:

```bash
docker compose run --rm p bash          # interactive shell with p on PATH
cd Projects/WarehouseFleet2026/WarehouseFleet && p compile
```
