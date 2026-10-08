#!/usr/bin/env bash
#
# Runs the keystroke budget alone and prints its six measurements as a table (ADR-0082 §D5,
# plan docs/plans/pg-385-n2-page.md, PG-385 R-15).
#
#   scripts/editor-restyle-bench.sh [--large|--large-only] [--runs N] [--no-warmup]
#
# It runs only `PergamenumTests/EditorRestyleBudgetTests`, greps the `restyle-budget` lines
# the test prints (one per size and variant: `size=<bytes> variant=<prose|fences>
# cpu_ms=<min> wall_ms=<min> runs=<K>`), and prints them as a table. Milliseconds of the main
# thread's CPU time per keystroke, the minimum of K runs after a warm-up; wall time is shown
# for reading and is never what the test asserts.
#
# The exit status is `xcodebuild`'s own: a red assertion (a measurement above its ceiling) is
# exit 65 and still prints the table, because the numbers are the point of running it.
#
# The switches it sets are the test's own environment variables, which `xcodebuild` hands the
# test process with the `TEST_RUNNER_` prefix stripped (ADR-0082 §D9):
#
#   RESTYLE_BUDGET_200KB=1       the two 200 KB rows; set on every run here but --large-only.
#                                The per-turn suite (the Stop hook) leaves it unset and asserts
#                                the two 50 KB rows only.
#   RESTYLE_BUDGET_1MB=1|only    the two 1 MB rows, beside the others or alone.
#   RESTYLE_BUDGET_RUNS=N        N measured runs per case instead of 5 (3 at 1 MB).
#   RESTYLE_BUDGET_NO_WARMUP=1   no warm-up keystroke.
#   RESTYLE_BUDGET_50KB=0        no 50 KB rows; the CI workflow sets it (the ceilings are this machine's).
#
# It builds into its own DerivedData (`build/restyle-bench-dd`), never the default one the
# Stop hook's unit build uses: two xcodebuilds on one `build.db` produce "database is locked"
# reds that are nobody's defect (PG-183). It refuses to start beside another xcodebuild on this
# project (the same refusal `scripts/uitests.sh` makes, with a narrower match, see below): a
# measurement taken while another build holds the CPU is not one to read.
#
# bash 3.2 (macOS): no `mapfile`, no associative arrays.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 2

# (none)        the four rows up to 200 KB
# --large       also measure the two 1 MB cases (minutes per keystroke)
# --large-only  only the two 1 MB cases
# --runs N      N measured runs per case instead of 5 (3 at 1 MB)
# --no-warmup   skip the warm-up keystroke (only for a case where one keystroke takes minutes)
export TEST_RUNNER_RESTYLE_BUDGET_200KB=1
while [ $# -gt 0 ]; do
    case "$1" in
        --large) export TEST_RUNNER_RESTYLE_BUDGET_1MB=1 ;;
        --large-only) export TEST_RUNNER_RESTYLE_BUDGET_1MB=only; unset TEST_RUNNER_RESTYLE_BUDGET_200KB ;;
        --runs)
            shift
            case "${1:-}" in
                '' | *[!0-9]* | 0*) echo "--runs needs a positive integer, got: «${1:-}»" >&2; exit 2 ;;
            esac
            export TEST_RUNNER_RESTYLE_BUDGET_RUNS="$1" ;;
        --no-warmup) export TEST_RUNNER_RESTYLE_BUDGET_NO_WARMUP=1 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# Only a process whose name is `xcodebuild` counts, then only one whose arguments name this
# project. `pgrep -f` on the pattern alone also matched a shell whose command text merely
# mentions `xcodebuild ... Pergamenum` (another session polling for a run to finish) and
# refused with nothing building.
other=""
for pid in $(pgrep -x xcodebuild 2>/dev/null || true); do
    args=$(ps -o args= -p "$pid" 2>/dev/null || true)
    case "$args" in
        *Pergamenum*) other="${other}${pid} ${args}"$'\n' ;;
    esac
done
if [ -n "$other" ]; then
    printf 'editor-restyle-bench: another xcodebuild is running:\n%s' "$other" >&2
    echo "wait for it to finish and run again" >&2
    exit 2
fi

code=0
log=$(mktemp -t editor-restyle-bench.XXXXXX)
trap 'rm -f "$log"' EXIT

xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' \
    -derivedDataPath "$root/build/restyle-bench-dd" \
    -only-testing:PergamenumTests/EditorRestyleBudgetTests test > "$log" 2>&1 || code=$?

lines=$(grep -E '^restyle-budget size=' "$log" || true)

if [ -z "$lines" ]; then
    echo "no restyle-budget line in the log (xcodebuild exit $code); last lines:" >&2
    tail -n 25 "$log" >&2
    exit "$code"
fi

field() {
    # field <name> <line>: the value after `name=` up to the next space.
    printf '%s\n' "$2" | sed -n "s/.*[[:space:]]$1=\([^[:space:]]*\).*/\1/p"
}

printf '%-10s %-8s %10s %10s %5s\n' "size" "variant" "cpu_ms" "wall_ms" "runs"
printf '%-10s %-8s %10s %10s %5s\n' "----------" "--------" "----------" "----------" "-----"
printf '%s\n' "$lines" | while IFS= read -r line; do
    size=$(field size "$line")
    variant=$(field variant "$line")
    cpu=$(field cpu_ms "$line")
    wall=$(field wall_ms "$line")
    runs=$(field runs "$line")
    printf '%-10s %-8s %10s %10s %5s\n' "$((size / 1024)) KB" "$variant" "$cpu" "$wall" "$runs"
done

total=$( { grep -E '^restyle-budget-total ' "$log" || true; } | sed -n 's/.*total_wall_ms=\([0-9]*\).*/\1/p' | awk '{ s += $1 } END { if (NR) printf "%.1f", s / 1000 }')
if [ -n "$total" ]; then
    echo "per-case wall time of the suite (build and fixture included): ${total} s"
fi
summary=$( { grep -E 'Test run with .* (passed|failed)' "$log" || true; } | tail -n 1)
if [ -n "$summary" ]; then
    echo "$summary"
fi
exit "$code"
