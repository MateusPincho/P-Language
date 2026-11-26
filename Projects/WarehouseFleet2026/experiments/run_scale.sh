#!/usr/bin/env bash
# E8, scale: the same model with 4 zones instead of 3.
#
#   experiments/run_scale.sh <schedules> <seed> <zones>
#   experiments/run_scale.sh 10000 1 4
#
# NUM_ZONES() is a global constant, so this copies WarehouseFleet/ to
# .mutants/zones<zones>/, changes `return 3;` in NUM_ZONES() to `return <zones>;`,
# and runs, inside the container, from the copy:
#   p compile
#   p check -tc tcRandomTasks -s <schedules> --seed <seed>
#   p check -tc tcE8ThreeRobots -s <schedules> --seed <seed>
# Results are appended to experiments/results.tsv with the test case name
# suffixed by @<zones>zones. The 3-robot case on 3 zones is tcE8ThreeRobots in
# TestScript.p and runs with run_tests.sh.
set -euo pipefail
[[ $# -eq 3 ]] || { sed -n '2,16p' "$0" | sed 's|^# \?||'; exit 2; }
N="$1"; SEED="$2"; Z="$3"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd -- "$HERE/.." && pwd)"
REPO="$(cd -- "$PROJECT/../.." && pwd)"
COPY="$PROJECT/.mutants/zones$Z"
REL="${COPY#"$REPO"/}"
rm -rf "$COPY"; mkdir -p "$COPY" "$HERE/logs"
cp -r "$PROJECT/WarehouseFleet/"{PSrc,PSpec,PTst,WarehouseFleet.pproj} "$COPY/"
grep -q 'fun NUM_ZONES(): int { return 3; }' "$COPY/PSrc/Enums_Types_Events.p"
sed -i "s/fun NUM_ZONES(): int { return 3; }/fun NUM_ZONES(): int { return $Z; }/" "$COPY/PSrc/Enums_Types_Events.p"
docker compose --project-directory "$REPO" run --rm -T p bash -lc "cd $REL && p compile" > "$HERE/logs/zones${Z}_compile.log" 2>&1
for TC in tcRandomTasks tcE8ThreeRobots; do
  LOG="$HERE/logs/${TC}@${Z}zones_s${N}_seed${SEED}.log"
  docker compose --project-directory "$REPO" run --rm -T p bash -lc \
    "cd $REL && p check -tc $TC -s $N --seed $SEED -o PCheckerOutput/run" > "$LOG" 2>&1 || true
  bugs=$(grep -oE 'Found [0-9]+ bug' "$LOG" | tail -1 | grep -oE '[0-9]+' || echo "?")
  explored=$(grep -oE 'Explored [0-9]+ schedule' "$LOG" | tail -1 | grep -oE '[0-9]+' || echo "?")
  timelines=$(grep -oE 'Explored [0-9]+ timeline' "$LOG" | tail -1 | grep -oE '[0-9]+' || echo "?")
  secs=$(grep -oE 'Elapsed [0-9.]+ sec\.$' "$LOG" | tail -1 | grep -oE '[0-9]+\.[0-9]+' || echo "?")
  err=$(grep -h '<ErrorLog>' "$COPY"/PCheckerOutput/run/BugFinding/*.txt 2>/dev/null | head -1 | sed 's/<ErrorLog> //' || true)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -I)" "${TC}@${Z}zones" "$N" "$SEED" "$bugs" "$explored" "$timelines" "$secs" "$err" \
    | tee -a "$HERE/results.tsv"
done
rm -rf "$COPY"
