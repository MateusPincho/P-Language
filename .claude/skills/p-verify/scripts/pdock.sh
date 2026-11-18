#!/usr/bin/env bash
# Run a `p` command against a P project inside the p-language:latest container.
#
# The host has no P toolchain. The repo is bind-mounted at the SAME absolute
# path it has on the host (PROJECT_MOUNT in the gitignored .env), so a path
# means the same thing inside and out -- which is what lets this script take an
# ordinary host path and cd to it in the container.
#
# Usage:
#   pdock.sh <project-dir> compile
#   pdock.sh <project-dir> check --list-tests
#   pdock.sh <project-dir> check -tc tcFleetTwoPhase -s 100000
#   pdock.sh <project-dir> check -tc tcFleetNaive --replay <seed>
#
# <project-dir> is the directory containing the .pproj -- not the repo root, and
# not a parent. Compiling from the wrong level scatters PGenerated/ where no
# project lives.
#
# Anything after <project-dir> is passed to `p` verbatim.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  sed -n '2,20p' "$0" | sed 's|^# \?||'
  exit 2
fi

PROJECT_DIR="$1"; shift

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)"
IMAGE="p-language:latest"

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "pdock.sh: no such directory: $PROJECT_DIR" >&2
  exit 2
fi
ABS_PROJECT="$(cd -- "$PROJECT_DIR" && pwd)"

if ! compgen -G "$ABS_PROJECT/*.pproj" >/dev/null; then
  echo "pdock.sh: no .pproj in $ABS_PROJECT" >&2
  echo "          pass the directory that holds the .pproj file." >&2
  exit 2
fi

case "$ABS_PROJECT" in
  "$REPO_DIR"|"$REPO_DIR"/*) ;;
  *)
    echo "pdock.sh: $ABS_PROJECT is outside $REPO_DIR, so it is not in the" >&2
    echo "          container's bind mount and 'p' cannot see it." >&2
    exit 2 ;;
esac

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "pdock.sh: image $IMAGE missing, building (first run only)..." >&2
  docker compose --project-directory "$REPO_DIR" build >&2
fi

# `p` lives at /home/dev/.dotnet/tools/p, added to PATH for the dev user, so the
# shell must be a login shell for PATH to be set.
exec docker compose --project-directory "$REPO_DIR" run --rm -T p \
  bash -lc 'cd "$1" && shift && p "$@"' _ "$ABS_PROJECT" "$@"
