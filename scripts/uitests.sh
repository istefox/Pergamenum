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
#     fail on it anyway. The same holds after the run: one that started meanwhile is left
#     alone and named, never closed with the debris (PG-175).
#   - **The timings are printed beside the failures**, because a failure at ~60 s is a
#     launch that never happened and a failure at 8 s is a test with something to say.
#
#   - **It builds into its own DerivedData** (`build/uitests-dd`). The `Stop` hook builds the
#     unit suite into the default one at the end of every turn, and two xcodebuilds on one
#     `build.db` end with "database is locked" in whichever loses - which reads as a suite
#     failure and cost a day of reruns (PG-183). Separate paths make the collision
#     impossible instead of unlikely, and it refuses to start beside another xcodebuild.
#   - **It keeps the evidence.** A `.xcresult` bundle is written next to the log, so a red is
#     diagnosed from failure messages and screenshots instead of by running 24 minutes again
#     (`xcrun xcresulttool get test-results summary --path <bundle>`).
#   - **A failure that passes on the retry is a flake, not a red.** `-retry-tests-on-failure`
#     runs each failing test once more; the ones that recover are named apart from the ones
#     that do not, and a launch that never happened is labelled whatever its duration.
#
# Usage:  scripts/uitests.sh [-only-testing:...]
#         with no arguments the whole bundle runs; an argument REPLACES that selection
#         rather than adding to it, so a single suite can be run:
#         scripts/uitests.sh -only-testing:PergamenumUITests/TimelineHoursUITests
#
#         scripts/uitests.sh --affected
#         derives the selection from what differs from `main` (committed, staged, unstaged
#         and untracked), prints why, and runs only that - or nothing, when nothing that
#         differs can reach the UI. For iteration only: the rule in CLAUDE.md, the whole suite
#         before a merge to `main`, is not replaced by it.
#
# A run this long is best started away from the machine and read afterwards:
#         caffeinate -dimsu scripts/uitests.sh > /dev/null 2>&1 &

set -euo pipefail

readonly REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG="${TMPDIR:-/tmp}/pergamenum-uitests-$(date +%Y%m%d-%H%M%S).log"
# What a launch timeout costs, to the tenth. Anything at or past this is reported as a
# suspected timeout rather than as a real failure.
readonly TIMEOUT_SECONDS=59
readonly RESULT_BUNDLE="${LOG%.log}.xcresult"
readonly FOCUS_LOG="${LOG%.log}.focus"
# Not the default DerivedData: see the header. `build/` is gitignored.
readonly DERIVED_DATA="$REPO/build/uitests-dd"

cd "$REPO"

fail() {
    printf 'uitests: %s\n' "$1" >&2
    exit 1
}

# Sends SIGTERM and waits for the process to actually be gone rather than assuming `kill`
# returning means it already is - measured up to two seconds after the signal here. Anything
# still alive after this script hands control back can hold the global hot key into the next
# invocation, which is what let a run started right after this one fail on its first launches
# instead of never seeing the leftover at all (PG-076).
kill_and_wait() {
    local pid="$1"
    kill "$pid" 2>/dev/null || return 0
    for _ in $(seq 1 10); do
        ps -p "$pid" >/dev/null 2>&1 || return 0
        sleep 1
    done
    kill -9 "$pid" 2>/dev/null || true
}

# MARK: --affected

# One changed path to what it can reach: `ALL` (the whole suite), `NONE` (no UI run), or the
# UI-test classes that exercise it. Conservative on purpose: a path nobody mapped is `ALL`,
# because a selection that misses a class is a green run that says nothing about it, which is
# the failure this script exists to prevent. The editor, the app shell, the design system and
# everything in `Sources/Core` that is not named below reach too many classes to list.
classes_for_path() {
    case "$1" in
        UITests/DragSupport.swift) echo ALL ;;
        UITests/*UITests.swift)
            local base="${1#UITests/}"
            echo "${base%.swift}" ;;
        Sources/CLI/*|Sources/MCPServer/*|Sources/Connector/*) echo NONE ;;
        Sources/Features/Workspace/*|Sources/Core/Canvas/*|Sources/Vault/CanvasStore.swift|Sources/Vault/BoardFileOperations.swift|Sources/Vault/BoardTaskRecord.swift)
            echo "WorkspaceBoardUITests WorkspaceFocusUITests WorkspaceIntegrationUITests WorkspaceOpenStateUITests SidebarMoveUITests" ;;
        Sources/Features/Pratiche/*|Sources/Core/Pratiche/*|Sources/Core/Email/*)
            echo "PraticheUITests" ;;
        Sources/Features/Tasks/*|Sources/Core/Tasks/*|Sources/Core/Categories/*)
            echo "TaskTimeUITests TaskCategoriesUITests" ;;
        Sources/Features/Diary/*|Sources/Features/Today/*|Sources/Core/Diary/*|Sources/Calendar/*)
            echo "DayViewUITests DiaryUITests TimeBlockUITests TimelineHoursUITests TaskTimeUITests" ;;
        Sources/App/SparkleUpdateController*) echo "UpdateMenuUITests" ;;
        Tests/*|docs/*|*.md|.claude/*|.github/*|scripts/*|.gitignore|.swiftlint.yml) echo NONE ;;
        *) echo ALL ;;
    esac
}

affected_selection() {
    local base changed path cls
    base=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || true)
    [ -n "$base" ] || fail "--affected non trova il punto di partenza da main"
    changed=$( { git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u)
    if [ -z "$changed" ]; then
        printf 'uitests: --affected: nessuna differenza da main, nessun giro.\n'
        exit 0
    fi
    local wanted="" all_reason="" none_count=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        cls=$(classes_for_path "$path")
        case "$cls" in
            ALL) all_reason="${all_reason:-$path}" ;;
            NONE) none_count=$((none_count + 1)) ;;
            *) wanted="$wanted $cls" ;;
        esac
    done <<< "$changed"
    if [ -n "$all_reason" ]; then
        printf 'uitests: --affected: %s raggiunge troppe classi per elencarle, giro completo.\n' "$all_reason"
        selection=(-only-testing:PergamenumUITests)
        return
    fi
    if [ -z "${wanted// /}" ]; then
        printf 'uitests: --affected: %d file cambiati, nessuno raggiunge la UI, nessun giro.\n' "$none_count"
        exit 0
    fi
    selection=()
    for cls in $(printf '%s\n' $wanted | sort -u); do
        selection+=("-only-testing:PergamenumUITests/$cls")
    done
    printf 'uitests: --affected: %d classi: %s\n' "${#selection[@]}" \
        "$(printf '%s\n' "${selection[@]}" | sed 's|.*/||' | tr '\n' ' ')"
}

selection=()
if [ "${1:-}" = "--affected" ]; then
    [ "$#" -eq 1 ] || fail "--affected non si combina con altri argomenti"
    affected_selection
fi

# MARK: instances

# Every running copy of the app, as `pid<TAB>path`.
running_instances() {
    ps -Ao pid=,command= | grep 'Pergamenum.app/Contents/MacOS/Pergamenum' | grep -v grep \
        | sed -E 's/^ *([0-9]+) +(.*)$/\1	\2/' || true
}

# A copy out of /Applications is the one you use; anything under DerivedData or inside the
# test runner's container is debris from an earlier run. Sorted into `yours` and `debris`
# by this one function, called before the run and again after it, so the two moments cannot
# disagree about which copy is whose (PG-175: the second one used to close both). Both strings
# keep a newline after every line on purpose: `read` skips a final line without one, which is
# how the old `$(running_instances)` here never closed the last instance it listed.
yours=""
debris=""
partition_instances() {
    yours=""
    debris=""
    local line
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in
            *"/Applications/"*) yours="$yours$line
" ;;
            *) debris="$debris$line
" ;;
        esac
    done < <(running_instances)
}

partition_instances

if [ -n "$yours" ]; then
    printf 'uitests: una copia installata di Pergamenum è in esecuzione:\n%s\n' "$yours" >&2
    fail "chiudila prima di lanciare la suite - tiene il tasto globale e il giro fallirebbe comunque"
fi

if [ -n "$debris" ]; then
    printf 'uitests: istanze rimaste da un giro precedente, le chiudo:\n%s\n' "$debris"
    printf '%s' "$debris" | while IFS='	' read -r pid _; do
        [ -n "$pid" ] && kill_and_wait "$pid"
    done
fi

# Another xcodebuild on this project - the Stop hook's unit run, a build in a terminal - is
# not debris and is not this script's to kill. With its own DerivedData it could no longer
# corrupt the run, but it still fights the run for the CPU and for the display's focus, and a
# result taken beside it is not one to trust (PG-183).
if other=$(pgrep -fl 'xcodebuild.*Pergamenum' 2>/dev/null) && [ -n "$other" ]; then
    printf 'uitests: un altro xcodebuild è in corso:\n%s\n' "$other" >&2
    fail "aspetta che finisca e rilancia"
fi

# MARK: keep-focused

# Confirmed by reading the screen recording XCUITest attaches to a failure: another
# app taking frontmost mid-run - a Mail notification, another agent's own GUI
# automation running elsewhere on this Mac - makes XCUITest's screen-coordinate drag
# synthesis land on whatever window is actually on top instead of Pergamenum's. It
# fails silently rather than loudly: the accessibility identifier still resolves (it's
# Pergamenum's own AX tree, unaffected by what's on screen), so the failure reads as a
# broken gesture or an unreachable row, not as "wrong window". None of this needs a
# person at the keyboard - a background app raising itself is enough. Reasserting
# frontmost once a second for the whole run, not just at launch, is what catches a
# window raised partway through.
focus_pergamenum() {
    local front
    while true; do
        # One call: note who is frontmost, then reassert. Every time it was somebody else
        # is written to FOCUS_LOG, so a red can be laid against a stolen focus instead of
        # guessing at one (the loop itself has never been proven a cause or a cure).
        front=$(osascript -e 'tell application "System Events"
            set prev to name of first process whose frontmost is true
            set frontmost of (first process whose name is "Pergamenum") to true
            return prev
        end tell' 2>/dev/null || true)
        if [ -n "$front" ] && [ "$front" != "Pergamenum" ]; then
            printf '%s %s\n' "$(date +%H:%M:%S)" "$front" >>"$FOCUS_LOG"
        fi
        sleep 1
    done
}
focus_pergamenum &
readonly FOCUS_PID=$!
trap 'kill "$FOCUS_PID" 2>/dev/null || true' EXIT

# MARK: run

printf 'uitests: log in %s\n' "$LOG"
printf 'uitests: la macchina è occupata (la suite intera ~25 minuti), non toccare la tastiera\n\n'

# The whole bundle unless the caller named something narrower. Not both: two
# `-only-testing` arguments are a union, so appending one to the default would silently
# run everything and look like it had run one suite.
if [ "${#selection[@]}" -eq 0 ]; then
    if [ "$#" -gt 0 ]; then
        selection=("$@")
    else
        selection=(-only-testing:PergamenumUITests)
    fi
fi

# `set -e` is off for exactly the xcodebuild call: a red suite must not abort the script
# before the per-test timings and the instance cleanup below have run. Only `-e` is
# switched; `-u` and `-o pipefail` stay on throughout.
set +e
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$RESULT_BUNDLE" \
    -retry-tests-on-failure -test-iterations 2 \
    "${selection[@]}" \
    test >"$LOG" 2>&1
readonly RESULT=$?
set -e

kill "$FOCUS_PID" 2>/dev/null || true

# MARK: what failed, and whether it is real

printf '\n'
grep -E "^	 Executed [0-9]+ tests?" "$LOG" | tail -1 || true

failures=$(grep -E "^Test Case .* failed \(" "$LOG" || true)

# A test that failed and then passed on the retry is a flake: named, not counted. One that
# never passed is a real red. Told apart by looking for a `passed` line for the same test.
real=""
recovered=""
seen=""
while IFS= read -r line; do
    [ -n "$line" ] || continue
    name=$(printf '%s' "$line" | sed -E "s/.*'-\[(.*)\]'.*/\1/")
    case "$seen" in *"|$name|"*) continue ;; esac
    seen="$seen|$name|"
    if grep -qF "Test Case '-[$name]' passed (" "$LOG"; then
        recovered="$recovered$line
"
    else
        real="$real$line
"
    fi
done <<< "$failures"

if [ -z "$real" ] && [ "$RESULT" -eq 0 ]; then
    # Said out loud rather than left to be inferred from a count: the whole point of this
    # script is that the state of the suite stops being something somebody has to work out.
    printf '\nuitests: verde.\n'
fi
if [ -n "$recovered" ]; then
    printf '\nRipescati al secondo tentativo (flake, non un rosso):\n'
    printf '%s' "$recovered" | sed -E "s/^Test Case '-\[(.*)\]' failed \((.*)\)\.$/  \1  (\2)/"
fi
if [ -n "$real" ]; then
    printf '\nFallimenti:\n'
    printf '%s' "$real" | while IFS= read -r line; do
        # `Test Case '-[Suite testName]' failed (8.834 seconds).` - the seconds are the
        # tell: a test that took a whole minute did not fail, it never launched.
        seconds=$(printf '%s' "$line" | sed -E 's/.*failed \(([0-9]+)\.[0-9]+ seconds\).*/\1/')
        name=$(printf '%s' "$line" | sed -E "s/.*'-\[(.*)\]'.*/\1/")
        # The other tell, for the launch that fails at once (PG-181: 0.7 s, "Failed to get
        # launch progress"), which no duration threshold can see.
        if grep -F "error: -[$name]" "$LOG" \
            | grep -qE 'Failed to get launch progress|Failed to launch|LaunchServices|is not running'; then
            printf '  %ss  %s   ← fallimento di lancio, non un fallimento vero\n' "$seconds" "$name"
        elif [ "$seconds" -ge "$TIMEOUT_SECONDS" ] 2>/dev/null; then
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

# Only the debris. A copy out of /Applications that appeared while the run was going is the
# person's, launched after the pre-run check had passed, and closing it here is the one thing
# that check exists to refuse. It is reported, not touched.
partition_instances
if [ -n "$debris" ]; then
    printf '\nuitests: istanze sopravvissute al giro, le chiudo:\n%s\n' "$debris"
    printf '%s' "$debris" | while IFS='	' read -r pid _; do
        [ -n "$pid" ] && kill_and_wait "$pid"
    done
fi
if [ -n "$yours" ]; then
    printf '\nuitests: una copia installata di Pergamenum è partita durante il giro, la lascio aperta:\n%s\n' "$yours"
fi

if [ -s "$FOCUS_LOG" ]; then
    printf '\nuitests: il focus è stato di un altro %d volte (dettaglio in %s):\n' \
        "$(wc -l <"$FOCUS_LOG" | tr -d ' ')" "$FOCUS_LOG"
    awk '{ $1=""; print }' "$FOCUS_LOG" | sort | uniq -c | sort -rn | sed 's/^/  /'
fi

printf '\nuitests: log completo in %s\n' "$LOG"
printf 'uitests: risultato in %s\n' "$RESULT_BUNDLE"
printf 'uitests: per diagnosticare senza rilanciare: xcrun xcresulttool get test-results summary --path %s\n' "$RESULT_BUNDLE"
exit "$RESULT"
