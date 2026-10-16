#!/usr/bin/env bash
#
# The three acceptance gates of ADR-0091 as numbers, on a Release build (PG-401: G-ceiling-2, G-grow
# R-14, G-type R-15). Tests/PG401GateTests.swift measures; this script builds, runs it, prints one
# verdict table and exits 0 only when every row passes.
#
#   scripts/pg-401-gates.sh [--gate ceiling|grow|type|update] [--allow-debug] [--runs N]
#
#   G-ceiling-2  a keystroke in the middle of a note, thread CPU, all six rows (50 KB, 200 KB, 1 MB,
#                prose and fences), each against its ceiling in RestyleBudget.ceilings (fixed 2026-10-11);
#                PG401_CEILING_MS replaces all six with one figure.
#   G-grow       a 1 MB note: type at the end and in the middle, Cmd+Down, scroll to the end, click
#                low; the view stays on the same text, the caret is where it was put, no height is
#                an estimate afterwards. Wall times of the steps are printed, and judged only when
#                PG401_STEP_MS names a limit: nobody has fixed one.
#   G-type       a sentence typed into a 50 KB note one character at a time, the 95th percentile of
#                thread CPU per character against PG401_TYPE_MS (default 16, one 60 Hz frame).
#   G-ceiling-406  ADR-0096, only with `--gate update` (Tests/UpdatePathGateTests.swift): the same keystroke
#                followed by SwiftUI's update, in the person's window (VaultBrowser: top bar, note list,
#                editor, inspector), thread CPU, all six rows against PG406_CEILING_MS (default 20). The
#                same keystroke on the editor column alone is printed beside it as G-ceiling-406-editor,
#                never judged. PG406_ONLY=<bytes>-<variant> runs one case, and one row is then expected.
#
# The limits are environment variables so a different one is a visible choice, not an edit. The
# numbers do not say a build *feels* smooth, and the display pass and the SwiftUI update after the
# binding write are outside the measurement (G-ceiling-406 alone includes that update); they say the
# proposals in the ADR hold or do not.
#
# It builds a Release configuration into its own DerivedData (`build/pg401-gates-dd`), never the
# default one the Stop hook uses (two xcodebuilds on one `build.db` give "database is locked"), with
# `ENABLE_TESTABILITY=YES` so `@testable` links against optimised code, and `ENABLE_HARDENED_RUNTIME=NO`
# because the hardened runtime refuses to load the test bundle (see Project.swift). A Debug run is a
# FAIL unless `--allow-debug`: a Debug number is not a verdict on the shipped app.
#
# Another xcodebuild on this project at any moment of the run (the Stop hook's suite is the usual one)
# makes the numbers unreadable: the run is reported CONTAMINATED and exits 3, neither pass nor fail,
# and is rerun when the machine is quiet (the same verdict `scripts/uitests.sh --status` uses).
#
# Exit: 0 every row passes and every expected row is present; 1 a row fails or one is missing;
# 2 bad invocation or another xcodebuild running at the start; 3 contaminated; otherwise xcodebuild's
# own status when it printed no gate line at all.
#
# bash 3.2 (macOS): no `mapfile`, no associative arrays.

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root" || exit 2

configuration=Release
allow_debug=0
gate_only=""
while [ $# -gt 0 ]; do
    case "$1" in
        --gate)
            shift
            case "${1:-}" in
                ceiling | grow | type | update) gate_only="$1" ;;
                *) echo "--gate needs ceiling, grow, type or update, got: «${1:-}»" >&2; exit 2 ;;
            esac ;;
        --allow-debug) allow_debug=1; configuration=Debug ;;
        --runs)
            shift
            case "${1:-}" in
                '' | *[!0-9]* | 0*) echo "--runs needs a positive integer, got: «${1:-}»" >&2; exit 2 ;;
            esac
            export TEST_RUNNER_RESTYLE_BUDGET_RUNS="$1" ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# Same narrow match as editor-restyle-bench.sh: a process named xcodebuild whose arguments name this
# project, never a shell that merely mentions it.
other=""
for pid in $(pgrep -x xcodebuild 2>/dev/null || true); do
    args=$(ps -o args= -p "$pid" 2>/dev/null || true)
    case "$args" in
        *Pergamenum*) other="${other}${pid} ${args}"$'\n' ;;
    esac
done
if [ -n "$other" ]; then
    printf 'pg-401-gates: another xcodebuild is running:\n%s' "$other" >&2
    echo "wait for it to finish and run again: a measurement taken beside another build is not one to read" >&2
    exit 2
fi

export TEST_RUNNER_PG401_GATES=1
if [ -n "$gate_only" ]; then export TEST_RUNNER_PG401_GATE="$gate_only"; fi
# The 200 KB rows of the budget helpers are not what runs here, but `RestyleBudget.runs` is shared.
for v in PG401_CEILING_MS PG401_TYPE_MS PG401_STEP_MS PG406_CEILING_MS PG406_ONLY; do
    value=$(printenv "$v" || true)
    if [ -n "$value" ]; then export "TEST_RUNNER_$v=$value"; fi
done
# G-ceiling-406 is its own suite and runs only when asked for; every other choice runs PG401GateTests as before.
suite=PG401GateTests
gate_width=12
if [ "$gate_only" = "update" ]; then suite=UpdatePathGateTests; gate_width=20; fi

code=0
log=$(mktemp -t pg-401-gates.XXXXXX)
trap 'rm -f "$log"' EXIT

xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' \
    -configuration "$configuration" -derivedDataPath "$root/build/pg401-gates-dd" \
    ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO \
    "-only-testing:PergamenumTests/$suite" test > "$log" 2>&1 &
mine=$!

# While it runs, look every second for any other xcodebuild on this project.
contaminated=""
while kill -0 "$mine" 2>/dev/null; do
    for pid in $(pgrep -x xcodebuild 2>/dev/null || true); do
        [ "$pid" = "$mine" ] && continue
        args=$(ps -o args= -p "$pid" 2>/dev/null || true)
        case "$args" in
            *Pergamenum*) contaminated="$pid" ;;
        esac
    done
    sleep 1
done
wait "$mine" || code=$?

lines=$(grep -E '^pg401-gate gate=' "$log" || true)
if [ -z "$lines" ]; then
    echo "no pg401-gate line in the log (xcodebuild exit $code); last lines:" >&2
    tail -n 25 "$log" >&2
    exit "$code"
fi

field() {
    # field <name> <line>: the value after `name=` up to the next space.
    printf '%s\n' "$2" | sed -n "s/.*[[:space:]]$1=\([^[:space:]]*\).*/\1/p"
}

printf '%-*s %-26s %-14s %10s %8s %-7s %-8s\n' "$gate_width" "gate" "case" "metric" "value" "limit" "verdict" "build"
printf '%-*s %-26s %-14s %10s %8s %-7s %-8s\n' "$gate_width" "$(printf '%*s' "$gate_width" '' | tr ' ' '-')" \
    "--------------------------" "--------------" "----------" "--------" "-------" "--------"
fails=0
debug_rows=0
while IFS= read -r line; do
    verdict=$(field verdict "$line")
    build=$(field build "$line")
    if [ "$verdict" = "fail" ]; then fails=$((fails + 1)); fi
    if [ "$build" = "debug" ]; then debug_rows=$((debug_rows + 1)); fi
    printf '%-*s %-26s %-14s %10s %8s %-7s %-8s\n' "$gate_width" "$(field gate "$line")" "$(field case "$line")" \
        "$(field metric "$line")" "$(field value "$line")" "$(field limit "$line")" "$verdict" "$build"
done <<EOF
$lines
EOF
echo
echo "screen backing scale: $(field scale "$(printf '%s\n' "$lines" | head -n 1)")"

# Every expected row must be there: a gate whose test did not run is not a gate that passed.
count() { printf '%s\n' "$lines" | grep -c "$1" || true; }
missing=""
want_gate() { [ -z "$gate_only" ] || [ "$gate_only" = "$1" ]; }
if want_gate ceiling && [ "$(count 'gate=G-ceiling-2 .*metric=cpu_ms')" -lt 6 ]; then missing="${missing} G-ceiling-2(6 cpu_ms rows)"; fi
if want_gate grow && [ "$(count 'gate=G-grow .*metric=state')" -lt 6 ]; then missing="${missing} G-grow(6 steps)"; fi
if want_gate type && [ "$(count 'gate=G-type .*metric=p95_cpu_ms')" -lt 2 ]; then missing="${missing} G-type(2 p95 rows)"; fi
# Not through want_gate: with no --gate the update suite does not run, so its rows are not expected.
# PG406_ONLY names one case, so one row is the whole run.
update_rows=6
if [ -n "${PG406_ONLY:-}" ]; then update_rows=1; fi
if [ "$gate_only" = "update" ] && [ "$(count 'gate=G-ceiling-406 .*metric=cpu_ms')" -lt "$update_rows" ]; then
    missing="${missing} G-ceiling-406(${update_rows} cpu_ms rows)"
fi

summary=$( { grep -E 'Test run with .* (passed|failed)' "$log" || true; } | tail -n 1)
[ -n "$summary" ] && echo "$summary"

status=0
if [ -n "$contaminated" ]; then
    echo "CONTAMINATED: another xcodebuild on this project (pid $contaminated) ran during the measurement; the numbers above are not a verdict. Rerun on a quiet machine." >&2
    exit 3
fi
if [ "$debug_rows" -gt 0 ] && [ "$allow_debug" -eq 0 ]; then
    echo "FAIL: $debug_rows rows came from a Debug build, which is not a verdict on the shipped app" >&2
    status=1
fi
if [ -n "$missing" ]; then
    echo "FAIL: missing rows:$missing" >&2
    status=1
fi
if [ "$fails" -gt 0 ]; then
    echo "FAIL: $fails rows over their limit" >&2
    status=1
fi
if [ "$code" -ne 0 ] && [ "$fails" -eq 0 ] && [ -z "$missing" ]; then
    echo "FAIL: xcodebuild exited $code with no failing row; see the log tail" >&2
    tail -n 25 "$log" >&2
    status=1
fi
if [ "$status" -eq 0 ]; then
    echo "PASS: every gate row is within its limit on a $configuration build"
fi
exit "$status"
