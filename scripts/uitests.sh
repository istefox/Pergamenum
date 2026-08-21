#!/usr/bin/env bash
#
# Runs the UI suite the way it has to be run, and says what actually failed.
#
# The suite lives outside `.claude/test-cmd` for a reason that holds: XCUITest takes the
# machine, so a per-turn run terminated the app the person at the keyboard was using and
# left an instance holding the global hot key, which made the next launch fail. The price
# of that reason is a suite nobody sees between deliberate runs - on 2026-08-21 three of
# its sixty-seven tests turned out to have been red since before the milestone that was
# about to be merged, and nothing had said so (PG-033).
#
# This script is the other half of the answer. The written rule is in CLAUDE.md: the suite
# runs before every merge to `main`. What is here is everything about that run which is
# easy to get wrong:
#
#   - **Stale instances are killed first.** A full run started with one alive gives 18
#     failures that are not real, every one at exactly 60.2 s - the launch timeout - and
#     two hours went into blaming something else for that once already (PG-026).
#   - **An instance you are using is not killed.** A copy running out of /Applications is
#     yours, not debris, so this stops and asks rather than closing your window. It has to
#     stop rather than continue: that instance holds the global hot key and the run would
#     fail on it anyway.
#   - **The timings are printed beside the failures**, because a failure at ~60 s is a
#     launch that never happened and a failure at 8 s is a test with something to say.
#
# Usage:  scripts/uitests.sh [-only-testing:...]
#         with no arguments the whole bundle runs; an argument REPLACES that selection
#         rather than adding to it, so a single suite can be run:
#         scripts/uitests.sh -only-testing:PergamenumUITests/TimelineHoursUITests

set -euo pipefail

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG="${TMPDIR:-/tmp}/pergamenum-uitests-$(date +%Y%m%d-%H%M%S).log"
# What a launch timeout costs, to the tenth. Anything at or past this is reported as a
# suspected timeout rather than as a real failure.
readonly TIMEOUT_SECONDS=59

cd "$REPO"

fail() {
    printf 'uitests: %s\n' "$1" >&2
    exit 1
}

# MARK: instances

# Every running copy of the app, as `pid<TAB>path`.
running_instances() {
    ps -Ao pid=,command= | grep 'Pergamenum.app/Contents/MacOS/Pergamenum' | grep -v grep \
        | sed -E 's/^ *([0-9]+) +(.*)$/\1	\2/' || true
}

# A copy out of /Applications is the one you use; anything under DerivedData or inside the
# test runner's container is debris from an earlier run.
yours=""
debris=""
while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
        *"/Applications/"*) yours="$yours$line
" ;;
        *) debris="$debris$line
" ;;
    esac
done < <(running_instances)

if [ -n "$yours" ]; then
    printf 'uitests: una copia installata di Pergamenum è in esecuzione:\n%s\n' "$yours" >&2
    fail "chiudila prima di lanciare la suite - tiene il tasto globale e il giro fallirebbe comunque"
fi

if [ -n "$debris" ]; then
    printf 'uitests: istanze rimaste da un giro precedente, le chiudo:\n%s\n' "$debris"
    printf '%s' "$debris" | while IFS='	' read -r pid _; do
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    done
    sleep 2
fi

# MARK: run

printf 'uitests: log in %s\n' "$LOG"
printf 'uitests: la macchina è occupata per una decina di minuti, non toccare la tastiera\n\n'

# The whole bundle unless the caller named something narrower. Not both: two
# `-only-testing` arguments are a union, so appending one to the default would silently
# run everything and look like it had run one suite.
if [ "$#" -gt 0 ]; then
    selection=("$@")
else
    selection=(-only-testing:PergamenumUITests)
fi

set +e
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum \
    -destination 'platform=macOS' \
    "${selection[@]}" \
    test >"$LOG" 2>&1
readonly RESULT=$?
set -e

# MARK: what failed, and whether it is real

printf '\n'
grep -E "^	 Executed [0-9]+ tests?" "$LOG" | tail -1 || true

failures=$(grep -E "^Test Case .* failed \(" "$LOG" || true)
if [ -z "$failures" ] && [ "$RESULT" -eq 0 ]; then
    # Said out loud rather than left to be inferred from a count: the whole point of this
    # script is that the state of the suite stops being something somebody has to work out.
    printf '\nuitests: verde.\n'
fi
if [ -n "$failures" ]; then
    printf '\nFallimenti:\n'
    printf '%s\n' "$failures" | while IFS= read -r line; do
        # `Test Case '-[Suite testName]' failed (8.834 seconds).` - the seconds are the
        # tell: a test that took a whole minute did not fail, it never launched.
        seconds=$(printf '%s' "$line" | sed -E 's/.*failed \(([0-9]+)\.[0-9]+ seconds\).*/\1/')
        name=$(printf '%s' "$line" | sed -E "s/.*'-\[(.*)\]'.*/\1/")
        if [ "$seconds" -ge "$TIMEOUT_SECONDS" ] 2>/dev/null; then
            printf '  ~%ss  %s   ← sospetto timeout di lancio, non un fallimento vero\n' \
                "$seconds" "$name"
        else
            printf '  %ss  %s\n' "$seconds" "$name"
        fi
    done

    printf '\nMessaggi:\n'
    grep -E "error: -\[" "$LOG" | sed -E 's/^.*error: //' | sed 's/^/  /' || true
fi

# MARK: leave nothing behind

leftovers=$(running_instances)
if [ -n "$leftovers" ]; then
    printf '\nuitests: istanze sopravvissute al giro, le chiudo:\n%s\n' "$leftovers"
    printf '%s' "$leftovers" | while IFS='	' read -r pid _; do
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    done
fi

printf '\nuitests: log completo in %s\n' "$LOG"
exit "$RESULT"
