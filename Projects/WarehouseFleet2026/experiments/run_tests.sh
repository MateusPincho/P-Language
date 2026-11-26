#!/usr/bin/env bash
# Run test cases of the WarehouseFleet model in the p-language container.
#
#   experiments/run_tests.sh <schedules> <seed> <test case>...
#   experiments/run_tests.sh 10000 1 tcHeadOnV1 tcE4BlockAll
#
# p check -tc matches test names by PREFIX, so no test name in TestScript.p may
# be a prefix of another (otherwise one command runs several tests).
#
# For every test case this runs, from WarehouseFleet/ inside the container:
#   p check -tc <test case> -s <schedules> --seed <seed> -o PCheckerOutput/<test case>_s<schedules>_seed<seed>
# and appends one line per run to experiments/results.tsv:
#   date  test case  schedules  seed  bugs  schedules explored  timelines  seconds  failing monitor/message
# The checker's own output is kept in experiments/logs/.
# Compile first: docker compose run --rm p bash -lc 'cd Projects/WarehouseFleet2026/WarehouseFleet && p compile'
set -euo pipefail

[[ $# -ge 3 ]] || { sed -n '2,13p' "$0" | sed 's|^# \?||'; exit 2; }
N="$1"; SEED="$2"; shift 2

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/../../.." && pwd)"
PROJ=Projects/WarehouseFleet2026/WarehouseFleet
mkdir -p "$HERE/logs"

for TC in "$@"; do
  OUT="PCheckerOutput/${TC}_s${N}_seed${SEED}"
  LOG="$HERE/logs/${TC}_s${N}_seed${SEED}.log"
  docker compose --project-directory "$REPO" run --rm -T p bash -lc \
    "cd $PROJ && rm -rf $OUT && p check -tc $TC -s $N --seed $SEED -o $OUT" > "$LOG" 2>&1 || true
  bugs=$(grep -oE 'Found [0-9]+ bug' "$LOG" | tail -1 | grep -oE '[0-9]+' || echo "?")
  explored=$(grep -oE 'Explored [0-9]+ schedule' "$LOG" | tail -1 | grep -oE '[0-9]+' || echo "?")
  timelines=$(grep -oE 'Explored [0-9]+ timeline' "$LOG" | tail -1 | grep -oE '[0-9]+' || echo "?")
  secs=$(grep -oE 'Elapsed [0-9.]+ sec\.$' "$LOG" | tail -1 | grep -oE '[0-9]+\.[0-9]+' || echo "?")
  err=$(grep -h '<ErrorLog>' "$REPO/$PROJ/$OUT"/BugFinding/*.txt 2>/dev/null | head -1 | sed 's/<ErrorLog> //' || true)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -I)" "$TC" "$N" "$SEED" "$bugs" "$explored" "$timelines" "$secs" "$err" \
    | tee -a "$HERE/results.tsv"
done
