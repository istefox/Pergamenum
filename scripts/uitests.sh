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
#   - **A launch that never happened is labelled whatever its duration**, and counts as one of
#     the four signs that the machine, not the code, disturbed the run (next bullet).
#   - **What a run learns is shared.** A run over a clean tree writes a verdict keyed by the
#     tree hash into the git common dir, which every worktree and every session of this repo
#     sees. `--status` reads it in a second, a full run over a tree already verified is
#     skipped, and two sessions cannot run the suite at once. Twenty-five minutes of the
#     machine is paid once per tree, not once per chat.
#   - **A run the machine disturbed is neither green nor red.** Four signals are watched: an
#     installed copy of the app that appeared mid-run, a launch that failed or timed out, focus
#     taken by another app, an external monitor (sampled before the run and again after it).
#     Reds and at least one signal make the run `contaminated`, and only the failed tests are
#     rerun, once: a green rerun makes it `green`, a red rerun with no signal makes it `red`, a
#     rerun disturbed again leaves it `contaminated`. A run with no reds is `green` whatever the
#     signals - they are recorded, not acted on (PG-182, PG-186, PG-188).
#   - **A run that executed no test is an error, not a red.** It is reported, records nothing
#     and leaves the tree's existing verdict alone (PG-194).
#   - **A copy of the app that appears mid-run leaves its launch log behind.** About ten seconds
#     of `launchd` and `launchservicesd` around the copy's start time are saved beside the
#     `.xcresult`, as `<log>.launch` (PG-182). The log cannot be read forward and the copy is
#     found after the run, so the window is centred on the start time `ps` reports for it. A
#     copy that started and quit again inside the run is never seen at all.
#
# Usage:  scripts/uitests.sh [-only-testing:...]
#         with no arguments the whole bundle runs; an argument REPLACES that selection
#         rather than adding to it, so a single suite can be run:
#         scripts/uitests.sh -only-testing:PergamenumUITests/TimelineHoursUITests
#
#         scripts/uitests.sh --status
#         says whether this tree, and `main`, already has a verdict, and what changed since the
#         last full green one. Read-only, instant, safe at any moment.
#
#         scripts/uitests.sh --affected
#         derives the selection from what differs from the last full green verdict (or from
#         `main` when there is none), prints why, and runs only that - or nothing, when nothing
#         that differs can reach the UI. For iteration only: the rule in CLAUDE.md, the whole
#         suite before a merge to `main`, is not replaced by it.
#
#         scripts/uitests.sh --force ...
#         runs even though the tree already has a full green verdict.
#
#         scripts/uitests.sh --self-test
#         asserts the verdict logic offline: fabricated logs, focus logs, display listings and
#         reruns in a throwaway verdict directory, with no build, no xcodebuild and no GUI. It
#         stands alone - any other argument beside it, in any position, is refused - and is the
#         thing to run after touching this file. Read-only for the real verdicts.
#
# Exit code: 0 green, 1 red (or an error: a run that executed no test), 2 contaminated. A
# contaminated run does not block a merge by itself, and `--status` never counts it as verified;
# only a green one lets a later run be skipped.
#
# Environment, both there so a test of this logic never touches the real thing:
#         UITESTS_VERDICT_DIR    replaces the shared verdict directory.
#         UITESTS_FAKE_DISPLAYS  a file holding `system_profiler -json SPDisplaysDataType` output,
#                                read instead of the machine's displays by the monitor signal.
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
# The launch log kept when an installed copy appears mid-run (R-06). Not created otherwise.
readonly LAUNCH_LOG="${LOG%.log}.launch"
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
            echo "WorkspaceBoardUITests WorkspaceIntegrationUITests WorkspaceOpenStateUITests SidebarMoveUITests" ;;
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

# MARK: --self-test arguments

# `--self-test` asserts the verdict logic offline and must never touch the real, shared verdicts,
# so its own throwaway directory is fixed here, before `VERDICT_DIR` is, and whatever
# UITESTS_VERDICT_DIR said is ignored. It stands alone: any other argument beside it is refused
# before a single thing has been created.
SELF_TEST=0
for arg in "$@"; do
    if [ "$arg" = "--self-test" ]; then
        [ "$#" -eq 1 ] || fail "--self-test non si combina con altri argomenti"
        SELF_TEST=1
        UITESTS_VERDICT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pergamenum-uitests-selftest.XXXXXX")
    fi
done

# MARK: shared verdicts

# What one run learned is worth something to every session working on this repo, so it is
# written where all of them look: the git common dir, which every worktree shares. A verdict is
# keyed by the tree hash of HEAD, not by the commit: a merge commit whose tree equals the branch
# tree that was tested is the same code, and the same verdict. Only a clean tree gets one, since
# a green over uncommitted edits describes no commit. UITESTS_VERDICT_DIR exists so a test of
# this logic never writes into the real, shared directory.
common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd)
readonly VERDICT_DIR="${UITESTS_VERDICT_DIR:-$common_dir/uitests-verdicts}"
readonly LOCK="$VERDICT_DIR/running"

tree_of() { git rev-parse "$1^{tree}" 2>/dev/null; }
is_clean() { [ -z "$(git status --porcelain --untracked-files=normal)" ]; }
verdict_field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }
verdict_file() { printf '%s/%s.%s.verdict' "$VERDICT_DIR" "$1" "$2"; }
# The only test for "this verdict counts as verified": `green` and nothing else. A `contaminated`
# one is neither green nor red, so it never lets a run be skipped and never moves the point
# `--affected` counts from; every reader of a verdict goes through here (R-04).
is_green_file() { [ "$(verdict_field "$1" result)" = green ]; }

# The newest full green verdict whose commit is HEAD or one of its ancestors: the point from
# which "what changed" is the whole question.
last_verified_ancestor() {
    local f c
    for f in $(ls -t "$VERDICT_DIR"/*.full.verdict 2>/dev/null); do
        is_green_file "$f" || continue
        c=$(verdict_field "$f" commit)
        if git merge-base --is-ancestor "$c" HEAD 2>/dev/null; then
            printf '%s' "$c"
            return
        fi
    done
}

# What the difference from `base` (committed, staged, unstaged and untracked) can reach, into
# PLAN (ALL, NONE or LIST), PLAN_CLASSES, PLAN_REASON (the first path that forces ALL) and
# PLAN_NONE (how many changed paths reach nothing).
PLAN=""
PLAN_CLASSES=""
PLAN_REASON=""
PLAN_NONE=0
plan_from() {
    local changed path cls wanted=""
    PLAN=""
    PLAN_CLASSES=""
    PLAN_REASON=""
    PLAN_NONE=0
    changed=$( { git diff --name-only "$1"; git ls-files --others --exclude-standard; } | sort -u)
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        cls=$(classes_for_path "$path")
        case "$cls" in
            ALL) PLAN_REASON="${PLAN_REASON:-$path}" ;;
            NONE) PLAN_NONE=$((PLAN_NONE + 1)) ;;
            *) wanted="$wanted $cls" ;;
        esac
    done <<< "$changed"
    if [ -n "$PLAN_REASON" ]; then
        PLAN=ALL
    elif [ -z "${wanted// /}" ]; then
        PLAN=NONE
    else
        PLAN=LIST
        PLAN_CLASSES=$(printf '%s\n' $wanted | sort -u | tr '\n' ' ')
    fi
}

describe_plan() {
    case "$PLAN" in
        NONE) printf 'nessun giro: %d file cambiati, nessuno raggiunge la UI' "$PLAN_NONE" ;;
        ALL) printf 'giro completo: %s raggiunge troppe classi per elencarle' "$PLAN_REASON" ;;
        *) printf 'solo %s' "$PLAN_CLASSES" ;;
    esac
}

show_verdict() {
    local label="$1" tree="$2" scope f reasons
    for scope in full partial; do
        f=$(verdict_file "$tree" "$scope")
        if [ -f "$f" ]; then
            # The signals a run recorded, zero or more, comma-separated in the file (R-01).
            reasons=$(verdict_field "$f" reasons | sed 's/,/, /g')
            printf '  %-5s %-8s %s il %s, %s test (commit %s)%s\n' "$label" "$scope" \
                "$(verdict_field "$f" result)" "$(verdict_field "$f" date)" \
                "$(verdict_field "$f" executed)" "$(verdict_field "$f" commit | cut -c1-7)" \
                "${reasons:+; segnali: $reasons}"
        else
            printf '  %-5s %-8s nessun verdetto\n' "$label" "$scope"
        fi
    done
}

# Read-only and instant: it never touches the machine, so it can be asked at any moment by any
# session. Exit 0 when HEAD counts as verified (definition at the end of the function), 1 when
# a run is still owed.
status_report() {
    local head_tree main_tree base
    head_tree=$(tree_of HEAD)
    printf 'uitests: HEAD %s, albero %s, %s\n' "$(git rev-parse --short HEAD)" "${head_tree:0:7}" \
        "$(is_clean && echo pulito || echo 'con modifiche non committate')"
    show_verdict HEAD "$head_tree"
    main_tree=$(tree_of main || tree_of origin/main || true)
    if [ -n "$main_tree" ] && [ "$main_tree" != "$head_tree" ]; then
        show_verdict main "$main_tree"
    fi
    base=$(last_verified_ancestor)
    if [ -n "$base" ]; then
        plan_from "$base"
        printf 'uitests: ultimo verde completo tra gli antenati: %s; da allora %s\n' "${base:0:7}" "$(describe_plan)"
    else
        printf 'uitests: nessun verde completo tra gli antenati di HEAD\n'
    fi
    # Verified means: HEAD's own tree has a full green verdict, or nothing that differs from the
    # last full green one can reach the UI (a script, a doc, the ledger). A contaminated verdict
    # is neither: it is shown above with its signals and leaves a run still owed.
    is_green_file "$(verdict_file "$head_tree" full)" \
        || { [ -n "$base" ] && [ "$PLAN" = NONE ]; }
}

# MARK: --affected

affected_selection() {
    local base how cls
    base=$(last_verified_ancestor)
    if [ -n "$base" ]; then
        how="dall'ultimo verde completo ${base:0:7}"
    else
        base=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || true)
        [ -n "$base" ] || fail "--affected non trova il punto di partenza"
        how="da main, mai verificato"
    fi
    plan_from "$base"
    case "$PLAN" in
        NONE)
            printf 'uitests: --affected (%s): %s.\n' "$how" "$(describe_plan)"
            exit 0 ;;
        ALL)
            printf 'uitests: --affected (%s): %s.\n' "$how" "$(describe_plan)"
            selection=(-only-testing:PergamenumUITests)
            SCOPE=full ;;
        *)
            selection=()
            for cls in $PLAN_CLASSES; do
                selection+=("-only-testing:PergamenumUITests/$cls")
            done
            printf 'uitests: --affected (%s): %d classi: %s\n' "$how" "${#selection[@]}" "$PLAN_CLASSES" ;;
    esac
}

# MARK: the verdict

# What a finished run is, and what is written about it. Everything here takes its inputs as
# arguments and reads no global that a run sets, so `--self-test` can drive every branch with
# fabricated logs and no `xcodebuild` (R-07). Signal sets are space-separated strings, walked with
# `for`: bash 3.2 here has no associative arrays.

# The four ways the machine, not the code, disturbs a run, in the one order they are ever written.
# An installed copy of the app that appeared mid-run, a launch that failed or timed out, focus taken
# by another app, an external monitor (R-02).
readonly SIGNAL_NAMES="installed-copy launch-failure focus-taken external-monitor"

# The union of two signal sets, in `SIGNAL_NAMES` order and without duplicates. It walks the
# canonical list rather than sorting its arguments, so the order is a property of this file and
# not of whoever built the input.
merge_signals() {
    local name out=""
    for name in $SIGNAL_NAMES; do
        case " $1 $2 " in
            *" $name "*) out="$out${out:+ }$name" ;;
        esac
    done
    printf '%s' "$out"
}

# green, red, contaminated or error, from what the run executed, how many tests were red and which
# signals it saw. No test executed is decided first, whatever the signals: it is not a result at all
# (R-05, PG-194). No red is green whatever the signals: they are recorded, not acted on (R-03).
run_outcome() {
    local executed="$1" reds="$2" signals="$3"
    if [ "$executed" -eq 0 ]; then
        echo error
    elif [ "$reds" -eq 0 ]; then
        echo green
    elif [ -z "${signals// /}" ]; then
        echo red
    else
        echo contaminated
    fi
}

# The exit code of the script for a result: 0 green, 1 red, 2 contaminated (R-04). An error is a
# 1 as well - never a 0, which would pass it for a green, and never a 2, which would say the
# machine was to blame when nothing ran.
exit_code_for() {
    case "$1" in
        green) echo 0 ;;
        contaminated) echo 2 ;;
        *) echo 1 ;;
    esac
}

# The function that reruns the failed tests. A variable rather than a fixed call so that
# `--self-test` can put a fabricated one in its place; the real one is defined with the run below.
RERUN_HOOK=real_rerun
VERDICT_RESULT=""
VERDICT_REASONS=""
RERUN_EXECUTED=0
RERUN_REDS=0
RERUN_SIGNALS=""
RERUN_COVERED=0

# Settles a finished run into VERDICT_RESULT and VERDICT_REASONS. Reds and at least one signal
# rerun only the failed tests, once, through $RERUN_HOOK, which sets the four RERUN_ variables:
# how many tests the rerun executed, how many of them were red, its own signals, and whether it
# covered every test that failed the first time (1) or not (0). A rerun that did not cover them
# all settles nothing about the ones it left out, so it cannot make the run green. Green, red with
# no signal, or contaminated again if the rerun was disturbed or never got going (R-03).
settle_verdict() {
    local executed="$1" reds="$2" signals="$3"
    VERDICT_REASONS=$(merge_signals "$signals" "")
    VERDICT_RESULT=$(run_outcome "$executed" "$reds" "$signals")
    [ "$VERDICT_RESULT" = contaminated ] || return 0

    RERUN_EXECUTED=0
    RERUN_REDS=0
    RERUN_SIGNALS=""
    RERUN_COVERED=0
    "$RERUN_HOOK"
    VERDICT_REASONS=$(merge_signals "$signals" "$RERUN_SIGNALS")
    if [ "$RERUN_EXECUTED" -eq 0 ] || [ "$RERUN_COVERED" -ne 1 ]; then
        VERDICT_RESULT=contaminated
    elif [ "$RERUN_REDS" -eq 0 ]; then
        VERDICT_RESULT=green
    elif [ -z "${RERUN_SIGNALS// /}" ]; then
        VERDICT_RESULT=red
    else
        VERDICT_RESULT=contaminated
    fi
    return 0
}

# Writes the verdict record for a tree and a scope, in the flat `key=value` form `verdict_field`
# reads, with the signals as a comma-separated `reasons=` (R-01). A run that executed no test, or
# that ended in an error, is refused here - status 1, nothing written, the tree's existing verdict
# left as it was (R-05, PG-194) - so that no caller can forget the rule: a 0-test run once replaced
# an informative 98/120 with a `red` that said nothing.
write_verdict() {
    local tree="$1" commit="$2" date="$3" scope="$4" result="$5" executed="$6" reasons="$7"
    local sel="$8" bundle="$9" log="${10}" file tmp
    [ "$executed" -gt 0 ] 2>/dev/null || return 1
    case "$result" in
        green | red | contaminated) ;;
        *) return 1 ;;
    esac
    file=$(verdict_file "$tree" "$scope")
    tmp="$file.$$"
    {
        printf 'tree=%s\ncommit=%s\ndate=%s\nscope=%s\nresult=%s\nreasons=%s\nexecuted=%s\n' \
            "$tree" "$commit" "$date" "$scope" "$result" "${reasons// /,}" "$executed"
        printf 'selection=%s\nbundle=%s\nlog=%s\n' "$sel" "$bundle" "$log"
    } >"$tmp" && mv "$tmp" "$file"
}

# MARK: reading a run

# The last `Executed N tests` total of an xcodebuild log, not the one a single suite prints; 0 when
# there is none, which is what a run that never got as far as a test looks like.
count_executed() {
    local n
    n=$(grep -E $'^\t Executed [0-9]+ tests?' "$1" 2>/dev/null | tail -1 \
        | sed -E 's/.*Executed ([0-9]+) tests?.*/\1/' || true)
    printf '%s' "${n:-0}"
}

# How many tests failed. A run that exited non-zero without naming a single failed test still has
# one red in it: an unnamed failure is not a pass.
reds_from() {
    local n
    n=$(grep -cE "^Test Case .* failed \(" "$1" 2>/dev/null || true)
    n="${n:-0}"
    if [ "$n" -eq 0 ] && [ "$2" -ne 0 ]; then
        n=1
    fi
    printf '%s' "$n"
}

# The failed tests, one `-only-testing:PergamenumUITests/<Class>/<test>` per line, each once. It is
# what the rerun runs: only the tests that failed, never the whole suite.
failed_selection() {
    grep -E "^Test Case '-\[[^]]+\]' failed \(" "$1" 2>/dev/null \
        | sed -E "s/^Test Case '-\[([^.]+)\.([^ ]+) ([^]]+)\]'.*/-only-testing:\1\/\2\/\3/" \
        | sort -u || true
}

# 1 when an external display is connected, else 0 (R-02). The rule is the one measured on this
# machine: a display of `system_profiler`'s `spdisplays_ndrvs`, on any GPU, that does not carry the
# `spdisplays_connection_type == spdisplays_internal` key is external. It is read as JSON because
# the text form prints no connection line at all for an external display and counting displays by
# indentation is fragile. A listing that cannot be read is 0, never a signal made up.
# UITESTS_FAKE_DISPLAYS names a file holding that JSON, read instead of the machine.
external_monitor_present() {
    local listing
    if [ -n "${UITESTS_FAKE_DISPLAYS:-}" ]; then
        listing=$(cat "$UITESTS_FAKE_DISPLAYS" 2>/dev/null) || { echo 0; return 0; }
    else
        listing=$(/usr/sbin/system_profiler -json SPDisplaysDataType 2>/dev/null) || { echo 0; return 0; }
    fi
    printf '%s' "$listing" | python3 -c '
import json, sys
try:
    gpus = json.load(sys.stdin).get("SPDisplaysDataType", [])
    external = any(
        d.get("spdisplays_connection_type") != "spdisplays_internal"
        for gpu in gpus
        for d in gpu.get("spdisplays_ndrvs", [])
    )
except Exception:
    external = False
print(1 if external else 0)
' 2>/dev/null || echo 0
}

# The signals a finished run shows, in `SIGNAL_NAMES` order (R-02). $3 is 1 when an installed copy
# of the app appeared during the run, $4 and $5 are 1 when an external display was seen before and
# after it. A launch that failed is one of the tells the report below already labels, or a failed
# test as long as the launch timeout, or the automation mode that never came up.
collect_signals() {
    local log="$1" focus_log="$2" found="" secs slow=0
    [ "$3" = 1 ] && found="$found installed-copy"
    if grep -E "error: -\[" "$log" 2>/dev/null \
        | grep -qE 'Failed to get launch progress|Failed to launch|LaunchServices|is not running'; then
        found="$found launch-failure"
    elif grep -qF 'Timed out while enabling automation mode' "$log" 2>/dev/null; then
        found="$found launch-failure"
    else
        for secs in $(grep -E "^Test Case .* failed \(" "$log" 2>/dev/null \
            | sed -E 's/.*failed \(([0-9]+)\.[0-9]+ seconds\).*/\1/'); do
            if [ "$secs" -ge "$TIMEOUT_SECONDS" ] 2>/dev/null; then
                slow=1
            fi
        done
        if [ "$slow" -eq 1 ]; then
            found="$found launch-failure"
        fi
    fi
    if [ -s "$focus_log" ]; then
        found="$found focus-taken"
    fi
    if [ "$4" = 1 ] || [ "$5" = 1 ]; then
        found="$found external-monitor"
    fi
    merge_signals "$found" ""
}

# The window of launch log kept around the moment an installed copy started (R-06, PG-182): five
# seconds either side of the start time `ps -o lstart=` reports for it, as `START|END` in the form
# `log show` takes. A time that cannot be read is no window: status 1, nothing printed.
log_window_around() {
    local start
    start=$(date -j -f "%a %b %e %H:%M:%S %Y" "$1" +%s 2>/dev/null) || return 1
    printf '%s|%s\n' "$(date -r $((start - 5)) '+%Y-%m-%d %H:%M:%S')" \
        "$(date -r $((start + 5)) '+%Y-%m-%d %H:%M:%S')"
}

# MARK: --self-test

# Asserts the verdict logic above with no build, no GUI and no app: logs, focus logs, display
# listings and reruns are all fabricated inside the throwaway directory this mode was given at the
# top of the file. It goes by `scripts/appcast.py --self-test`: named checks, a count at the end,
# and the first check that fails stops it with a non-zero exit. What it pins is the decision table
# (R-03), the exit codes and the rule that only a green verdict counts as verified (R-04), and the
# zero-test error state (R-05); it says nothing about the machine or about xcodebuild.
SELFTEST_COUNT=0
SELFTEST_OK=0

expect_eq() {
    local description="$1" wanted="$2" got="$3"
    if [ "$wanted" != "$got" ]; then
        printf 'uitests: self-test fallito: %s\n  atteso:   [%s]\n  ottenuto: [%s]\n  (file del controllo in %s)\n' \
            "$description" "$wanted" "$got" "$VERDICT_DIR" >&2
        exit 1
    fi
    SELFTEST_COUNT=$((SELFTEST_COUNT + 1))
    printf '  ok  %s\n' "$description"
}

# `si` when $1 contains $2, so that a substring check can go through expect_eq as well.
contains() {
    case "$1" in *"$2"*) echo si ;; *) echo no ;; esac
}

# A rerun that reports whatever the check fabricated, so `settle_verdict` can be driven through
# every one of its branches without a second xcodebuild.
FAKE_RERUN_CALLS=0
FAKE_RERUN_EXECUTED=0
FAKE_RERUN_REDS=0
FAKE_RERUN_SIGNALS=""
FAKE_RERUN_COVERED=0
fake_rerun() {
    FAKE_RERUN_CALLS=$((FAKE_RERUN_CALLS + 1))
    RERUN_EXECUTED="$FAKE_RERUN_EXECUTED"
    RERUN_REDS="$FAKE_RERUN_REDS"
    RERUN_SIGNALS="$FAKE_RERUN_SIGNALS"
    RERUN_COVERED="$FAKE_RERUN_COVERED"
}

# selftest_settle <executed> <reds> <signals> [<rerun executed> <rerun reds> <rerun signals> <covered>]
selftest_settle() {
    FAKE_RERUN_CALLS=0
    FAKE_RERUN_EXECUTED="${4:-0}"
    FAKE_RERUN_REDS="${5:-0}"
    FAKE_RERUN_SIGNALS="${6:-}"
    FAKE_RERUN_COVERED="${7:-0}"
    RERUN_HOOK=fake_rerun
    settle_verdict "$1" "$2" "$3"
}

# Only ever empties the directory this mode made itself, and keeps it when a check failed so the
# fabricated files can be read.
selftest_cleanup() {
    [ "$SELFTEST_OK" -eq 1 ] || return 0
    case "$VERDICT_DIR" in
        */pergamenum-uitests-selftest.*)
            rm -f "$VERDICT_DIR"/* 2>/dev/null || true
            rmdir "$VERDICT_DIR" 2>/dev/null || true ;;
    esac
    return 0
}

self_test() {
    local d="$VERDICT_DIR" head_tree head_commit f before out rc s
    case "$d" in
        */pergamenum-uitests-selftest.*) ;;
        *) fail "--self-test senza la sua cartella temporanea: mi fermo prima di scrivere altrove" ;;
    esac
    trap selftest_cleanup EXIT
    head_tree=$(tree_of HEAD)
    head_commit=$(git rev-parse HEAD)
    printf 'uitests.sh --self-test: offline, verdetti e log finti in %s\n' "$d"

    # R-03: what a finished run is, before any rerun.
    expect_eq "nessun test eseguito: errore, non rosso (PG-194)" error "$(run_outcome 0 1 "")"
    expect_eq "nessun test eseguito e un segnale: ancora errore" error "$(run_outcome 0 1 "focus-taken")"
    expect_eq "nessun rosso e nessun segnale: verde" green "$(run_outcome 12 0 "")"
    expect_eq "nessun rosso e tutti i segnali: verde, i segnali si registrano e basta" green "$(run_outcome 12 0 "$SIGNAL_NAMES")"
    expect_eq "rossi senza segnali: rosso" red "$(run_outcome 12 3 "")"
    for s in $SIGNAL_NAMES; do
        expect_eq "rossi e il segnale $s: contaminato" contaminated "$(run_outcome 12 3 "$s")"
    done
    expect_eq "i segnali si scrivono sempre nello stesso ordine, senza doppioni" \
        "installed-copy focus-taken" "$(merge_signals "focus-taken installed-copy" "focus-taken")"

    # R-03: the single rerun and what it settles.
    selftest_settle 12 0 ""
    expect_eq "verde senza segnali: nessun rilancio" "green 0" "$VERDICT_RESULT $FAKE_RERUN_CALLS"
    selftest_settle 12 0 "focus-taken external-monitor"
    expect_eq "verde con segnali: resta verde, nessun rilancio, i segnali restano scritti" \
        "green 0 focus-taken external-monitor" "$VERDICT_RESULT $FAKE_RERUN_CALLS $VERDICT_REASONS"
    selftest_settle 12 2 ""
    expect_eq "rossi senza segnali: rosso, nessun rilancio" "red 0" "$VERDICT_RESULT $FAKE_RERUN_CALLS"
    selftest_settle 12 2 "focus-taken" 2 0 "" 1
    expect_eq "rossi con un segnale e rilancio verde: verde, un solo rilancio" \
        "green 1 focus-taken" "$VERDICT_RESULT $FAKE_RERUN_CALLS $VERDICT_REASONS"
    selftest_settle 12 2 "external-monitor" 2 1 "" 1
    expect_eq "rilancio rosso senza segnali: rosso, un solo rilancio" "red 1" "$VERDICT_RESULT $FAKE_RERUN_CALLS"
    selftest_settle 12 2 "focus-taken" 2 1 "installed-copy" 1
    expect_eq "rilancio rosso e disturbato: resta contaminato, con i motivi di entrambi i giri" \
        "contaminated 1 installed-copy focus-taken" "$VERDICT_RESULT $FAKE_RERUN_CALLS $VERDICT_REASONS"
    selftest_settle 12 2 "focus-taken" 0 0 "" 0
    expect_eq "rilancio che non è partito: resta contaminato" "contaminated 1" "$VERDICT_RESULT $FAKE_RERUN_CALLS"
    selftest_settle 12 2 "focus-taken" 1 0 "" 0
    expect_eq "rilancio verde che non copre tutti i rossi: resta contaminato" \
        "contaminated 1" "$VERDICT_RESULT $FAKE_RERUN_CALLS"
    selftest_settle 0 1 "focus-taken"
    expect_eq "zero test: errore, e nessun rilancio" "error 0" "$VERDICT_RESULT $FAKE_RERUN_CALLS"

    # R-04: the exit codes.
    expect_eq "uscita 0 per il verde" 0 "$(exit_code_for green)"
    expect_eq "uscita 1 per il rosso" 1 "$(exit_code_for red)"
    expect_eq "uscita 2 per il contaminato" 2 "$(exit_code_for contaminated)"
    expect_eq "uscita 1 per l'errore: mai 0, mai 2" 1 "$(exit_code_for error)"

    # R-01, R-04: the record, and the rule that only green counts as verified.
    rm -f "$d"/*.verdict
    f=$(verdict_file "$head_tree" full)
    write_verdict "$head_tree" "$head_commit" "2026-09-21 10:00" full contaminated 121 \
        "focus-taken external-monitor" "-only-testing:PergamenumUITests" "$d/x.xcresult" "$d/x.log"
    expect_eq "il verdetto registra il terzo risultato" contaminated "$(verdict_field "$f" result)"
    expect_eq "il verdetto registra i motivi, uno dopo l'altro" \
        "focus-taken,external-monitor" "$(verdict_field "$f" reasons)"
    expect_eq "il verdetto registra quanti test sono girati" 121 "$(verdict_field "$f" executed)"
    expect_eq "un contaminato non è verde: non fa saltare un giro completo" \
        no "$(if is_green_file "$f"; then echo si; else echo no; fi)"
    expect_eq "last_verified_ancestor: un contaminato non è un punto verificato" "" "$(last_verified_ancestor)"
    rc=0
    out=$(status_report) || rc=$?
    expect_eq "--status: con un contaminato HEAD non è verificato (uscita 1)" 1 "$rc"
    expect_eq "--status: nomina il risultato" si "$(contains "$out" contaminated)"
    expect_eq "--status: nomina i motivi" si "$(contains "$out" "focus-taken, external-monitor")"
    write_verdict "$head_tree" "$head_commit" "2026-09-21 11:00" full green 121 "" \
        "-only-testing:PergamenumUITests" "$d/x.xcresult" "$d/x.log"
    expect_eq "un verde è verde" si "$(if is_green_file "$f"; then echo si; else echo no; fi)"
    expect_eq "last_verified_ancestor: un verde è un punto verificato" "$head_commit" "$(last_verified_ancestor)"
    rc=0
    out=$(status_report) || rc=$?
    expect_eq "--status: con un verde HEAD è verificato (uscita 0)" 0 "$rc"

    # R-05: a run that executed no test is an error, never a stored red, and never an overwrite.
    before=$(cat "$f")
    rc=0
    write_verdict "$head_tree" "$head_commit" "2026-09-21 12:00" full red 0 "" \
        "-only-testing:PergamenumUITests" "$d/x.xcresult" "$d/x.log" || rc=$?
    expect_eq "zero test non si registra come rosso" 1 "$rc"
    expect_eq "e non tocca il verdetto che l'albero aveva già" "$before" "$(cat "$f")"
    rc=0
    write_verdict "$head_tree" "$head_commit" "2026-09-21 12:00" full error 5 "" \
        "-only-testing:PergamenumUITests" "$d/x.xcresult" "$d/x.log" || rc=$?
    expect_eq "un esito di errore non si registra mai" 1 "$rc"
    rm -f "$f"
    write_verdict "$head_tree" "$head_commit" "2026-09-21 12:00" full red 0 "" \
        "-only-testing:PergamenumUITests" "$d/x.xcresult" "$d/x.log" || true
    expect_eq "senza un verdetto già presente, zero test non ne crea uno" \
        no "$(if [ -e "$f" ]; then echo si; else echo no; fi)"

    # R-02: the four signals, read off fabricated logs, focus logs and display listings.
    printf '%s\n' \
        "Test Case '-[PergamenumUITests.DayViewUITests testA]' passed (4.100 seconds)." \
        $'\t Executed 5 tests, with 0 failures (0 unexpected) in 20.000 (20.010) seconds' >"$d/green.log"
    printf '%s\n' \
        "/Users/x/UITests/DayViewUITests.swift:40: error: -[PergamenumUITests.DayViewUITests testA] : XCTAssertTrue failed - la riga non c'è" \
        "Test Case '-[PergamenumUITests.DayViewUITests testA]' failed (8.834 seconds)." \
        $'\t Executed 3 tests, with 1 failure (0 unexpected) in 20.000 (20.010) seconds' >"$d/red-plain.log"
    printf '%s\n' \
        "/Users/x/UITests/DiaryUITests.swift:12: error: -[PergamenumUITests.DiaryUITests testB] : Failed to get launch progress" \
        "Test Case '-[PergamenumUITests.DiaryUITests testB]' failed (0.712 seconds)." \
        $'\t Executed 3 tests, with 1 failure (0 unexpected) in 9.000 (9.010) seconds' >"$d/red-launch.log"
    printf '%s\n' \
        "/Users/x/UITests/DiaryUITests.swift:12: error: -[PergamenumUITests.DiaryUITests testB] : XCTAssertTrue failed - non è apparso" \
        "Test Case '-[PergamenumUITests.DiaryUITests testB]' failed (60.204 seconds)." \
        $'\t Executed 3 tests, with 1 failure (0 unexpected) in 70.000 (70.010) seconds' >"$d/red-timeout.log"
    printf '%s\n' \
        "Test Case '-[PergamenumUITests.DayViewUITests testA]' failed (8.834 seconds)." \
        "Test Case '-[PergamenumUITests.DiaryUITests testC]' failed (9.102 seconds)." \
        $'\t Executed 3 tests, with 1 failure (0 unexpected) in 20.000 (20.010) seconds' \
        $'\t Executed 121 tests, with 2 failures (0 unexpected) in 900.000 (900.010) seconds' >"$d/two-failures.log"
    printf '%s\n' "error: Cannot build workspace Pergamenum.xcworkspace" >"$d/zero.log"
    : >"$d/focus-empty"
    printf '%s\n' "14:03:11 Mail" >"$d/focus-taken"

    expect_eq "count_executed: l'ultimo totale, non quello di una suite" 121 "$(count_executed "$d/two-failures.log")"
    expect_eq "count_executed: un log senza totale conta zero" 0 "$(count_executed "$d/zero.log")"
    expect_eq "reds_from: un rosso per ogni test fallito" 2 "$(reds_from "$d/two-failures.log" 65)"
    expect_eq "reds_from: uscita non zero senza test nominati è comunque un rosso" 1 "$(reds_from "$d/zero.log" 65)"
    expect_eq "reds_from: un giro verde non ha rossi" 0 "$(reds_from "$d/green.log" 0)"
    expect_eq "failed_selection: i test falliti, nella forma di -only-testing" \
        $'-only-testing:PergamenumUITests/DayViewUITests/testA\n-only-testing:PergamenumUITests/DiaryUITests/testC' \
        "$(failed_selection "$d/two-failures.log")"

    expect_eq "nessun segnale su un rosso qualunque" "" \
        "$(collect_signals "$d/red-plain.log" "$d/focus-empty" 0 0 0)"
    expect_eq "segnale: focus preso da un'altra app" focus-taken \
        "$(collect_signals "$d/red-plain.log" "$d/focus-taken" 0 0 0)"
    expect_eq "segnale: copia installata comparsa durante il giro" installed-copy \
        "$(collect_signals "$d/red-plain.log" "$d/focus-empty" 1 0 0)"
    expect_eq "segnale: lancio fallito" launch-failure \
        "$(collect_signals "$d/red-launch.log" "$d/focus-empty" 0 0 0)"
    expect_eq "segnale: timeout di lancio (un rosso lungo quanto il timeout)" launch-failure \
        "$(collect_signals "$d/red-timeout.log" "$d/focus-empty" 0 0 0)"
    expect_eq "segnale: monitor esterno visto prima del giro" external-monitor \
        "$(collect_signals "$d/red-plain.log" "$d/focus-empty" 0 1 0)"
    expect_eq "segnale: monitor esterno visto solo dopo il giro" external-monitor \
        "$(collect_signals "$d/red-plain.log" "$d/focus-empty" 0 0 1)"
    expect_eq "tutti e quattro i segnali, nell'ordine di sempre" "$SIGNAL_NAMES" \
        "$(collect_signals "$d/red-launch.log" "$d/focus-taken" 1 1 1)"

    printf '%s\n' '{"SPDisplaysDataType":[{"_name":"Apple M5 Max","spdisplays_ndrvs":[{"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal"}]}]}' >"$d/displays-internal.json"
    printf '%s\n' '{"SPDisplaysDataType":[{"_name":"Apple M5 Max","spdisplays_ndrvs":[{"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal"},{"_name":"LG FULL HD"}]}]}' >"$d/displays-external.json"
    printf '%s\n' '{"SPDisplaysDataType":[{"_name":"GPU A","spdisplays_ndrvs":[{"_name":"Color LCD","spdisplays_connection_type":"spdisplays_internal"}]},{"_name":"GPU B","spdisplays_ndrvs":[{"_name":"DELL U2723QE"}]}]}' >"$d/displays-second-gpu.json"
    printf '%s\n' '{"SPDisplaysDataType":[{"_name":"Apple M5 Max","spdisplays_ndrvs":[{"_name":"LG FULL HD"}]}]}' >"$d/displays-lid-closed.json"
    printf '%s\n' '{"SPDisplaysDataType":[{"_name":"GPU A"}]}' >"$d/displays-none.json"
    printf '%s\n' 'not json at all' >"$d/displays-garbage.json"
    expect_eq "monitor: solo lo schermo interno non è un monitor esterno" 0 \
        "$(UITESTS_FAKE_DISPLAYS="$d/displays-internal.json" external_monitor_present)"
    expect_eq "monitor: uno schermo senza il tipo di connessione interno è esterno" 1 \
        "$(UITESTS_FAKE_DISPLAYS="$d/displays-external.json" external_monitor_present)"
    expect_eq "monitor: lo si vede anche sulla seconda GPU" 1 \
        "$(UITESTS_FAKE_DISPLAYS="$d/displays-second-gpu.json" external_monitor_present)"
    expect_eq "monitor: lo si vede anche a coperchio chiuso, senza lo schermo interno" 1 \
        "$(UITESTS_FAKE_DISPLAYS="$d/displays-lid-closed.json" external_monitor_present)"
    expect_eq "monitor: una GPU senza schermi non ne ha" 0 \
        "$(UITESTS_FAKE_DISPLAYS="$d/displays-none.json" external_monitor_present)"
    expect_eq "monitor: un elenco illeggibile non inventa un segnale" 0 \
        "$(UITESTS_FAKE_DISPLAYS="$d/displays-garbage.json" external_monitor_present)"
    expect_eq "monitor: un file che non c'è non inventa un segnale" 0 \
        "$(UITESTS_FAKE_DISPLAYS="$d/displays-missing.json" external_monitor_present)"

    # R-06: the window of launch log saved around the moment a copy appeared.
    expect_eq "finestra del log: cinque secondi prima e dopo l'avvio della copia" \
        "2026-09-21 14:54:15|2026-09-21 14:54:25" "$(TZ=UTC log_window_around "Sun Sep 21 14:54:20 2026")"
    rc=0
    log_window_around "non è una data" >/dev/null 2>&1 || rc=$?
    expect_eq "finestra del log: un orario illeggibile non inventa una finestra" 1 "$rc"

    # --self-test stands alone. The nested call is told it is nested, so a refusal that ever broke
    # would end here as a failed check instead of a self-test spawning self-tests without end.
    if [ -z "${UITESTS_SELFTEST_NESTED:-}" ]; then
        rc=0
        out=$(UITESTS_SELFTEST_NESTED=1 "$BASH" "$REPO/scripts/uitests.sh" --self-test --status 2>&1) || rc=$?
        expect_eq "--self-test non si combina con altri argomenti (uscita 1)" 1 "$rc"
        expect_eq "--self-test dice perché si è rifiutato" si "$(contains "$out" "non si combina")"
    fi

    SELFTEST_OK=1
    printf '\nuitests.sh --self-test: %d controlli, tutti passati\n' "$SELFTEST_COUNT"
}

if [ "$SELF_TEST" -eq 1 ]; then
    self_test
    exit 0
fi

FORCE=0
SCOPE=partial
selection=()
if [ "${1:-}" = "--force" ]; then
    FORCE=1
    shift
fi
if [ "${1:-}" = "--status" ]; then
    [ "$#" -eq 1 ] || fail "--status non si combina con altri argomenti"
    if status_report; then exit 0; else exit 1; fi
fi
if [ "${1:-}" = "--affected" ]; then
    [ "$#" -eq 1 ] || fail "--affected non si combina con altri argomenti"
    affected_selection
elif [ "$#" -eq 0 ]; then
    SCOPE=full
fi

# The tree this run is about, taken before anything moves. A full run over a tree that already
# has a full green verdict is a run somebody else already paid for.
readonly START_TREE=$(tree_of HEAD)
if is_clean; then START_CLEAN=1; else START_CLEAN=0; fi
readonly START_CLEAN
if [ "$SCOPE" = full ] && [ "$START_CLEAN" -eq 1 ] && [ "$FORCE" -eq 0 ]; then
    verdict=$(verdict_file "$START_TREE" full)
    if [ -f "$verdict" ] && [ "$(verdict_field "$verdict" result)" = green ]; then
        printf 'uitests: questo albero è già verificato: verde il %s, %s test, commit %s. Nessun giro (--force per rifarlo).\n' \
            "$(verdict_field "$verdict" date)" "$(verdict_field "$verdict" executed)" \
            "$(verdict_field "$verdict" commit | cut -c1-7)"
        exit 0
    fi
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

# Closes what `partition_instances` filed as debris, naming it under the header given. One place
# for the pre-run sweep, the sweep before a launch-failure rerun and the post-run cleanup.
close_debris() {
    [ -n "$debris" ] || return 0
    printf '%s\n%s\n' "$1" "$debris"
    printf '%s' "$debris" | while IFS='	' read -r pid _; do
        [ -n "$pid" ] && kill_and_wait "$pid"
    done
}

partition_instances

if [ -n "$yours" ]; then
    printf 'uitests: una copia installata di Pergamenum è in esecuzione:\n%s\n' "$yours" >&2
    fail "chiudila prima di lanciare la suite - tiene il tasto globale e il giro fallirebbe comunque"
fi

close_debris "uitests: istanze rimaste da un giro precedente, le chiudo:"

# Another xcodebuild on this project - the Stop hook's unit run, a build in a terminal - is
# not debris and is not this script's to kill. With its own DerivedData it could no longer
# corrupt the run, but it still fights the run for the CPU and for the display's focus, and a
# result taken beside it is not one to trust (PG-183).
if other=$(pgrep -fl 'xcodebuild.*Pergamenum' 2>/dev/null) && [ -n "$other" ]; then
    printf 'uitests: un altro xcodebuild è in corso:\n%s\n' "$other" >&2
    fail "aspetta che finisca e rilancia"
fi

# Two sessions running the suite at once is one run too many: they fight for the pointer, the
# focus and the global hot key, and the second one's result is noise. The lock names who has
# it, so the other session knows there is a verdict coming that will be its own as well.
FOCUS_PID=""
rerun_focus=""
cleanup() {
    kill $FOCUS_PID $rerun_focus 2>/dev/null || true
    [ "$(cut -f1 "$LOCK" 2>/dev/null)" = "$$" ] && rm -f "$LOCK"
    return 0
}
mkdir -p "$VERDICT_DIR"
take_lock() {
    ( set -C; printf '%s\t%s\t%s\t%s\n' "$$" "$REPO" "$(date +%H:%M:%S)" "$SCOPE" >"$LOCK" ) 2>/dev/null
}
if ! take_lock; then
    if kill -0 "$(cut -f1 "$LOCK" 2>/dev/null)" 2>/dev/null; then
        printf 'uitests: un giro è già in corso (pid, cartella, ora, ambito):\n  %s\n' "$(tr '\t' ' ' <"$LOCK")" >&2
        fail "aspetta che finisca: il suo verdetto varrà anche per questa sessione (uitests.sh --status)"
    fi
    rm -f "$LOCK"
    take_lock || fail "non riesco a prendere il lock dei giri"
fi
trap cleanup EXIT

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
    local front out="${1:-$FOCUS_LOG}"
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
            printf '%s %s\n' "$(date +%H:%M:%S)" "$front" >>"$out"
        fi
        sleep 1
    done
}
focus_pergamenum &
FOCUS_PID=$!


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

# The external monitor is sampled, not polled: once here and once after the run, which sees it
# connected throughout, connected partway and disconnected partway for about 0.6 s of the machine
# (R-02). Before the run's first launch, so a display that is there from the start is counted.
MON_BEFORE=$(external_monitor_present)

# `set -e` is off for exactly the xcodebuild call: a red suite must not abort the script
# before the per-test timings and the instance cleanup below have run. Only `-e` is
# switched; `-u` and `-o pipefail` stay on throughout.
set +e
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$RESULT_BUNDLE" \
    "${selection[@]}" \
    test >"$LOG" 2>&1
RESULT=$?
set -e

kill "$FOCUS_PID" 2>/dev/null || true

MON_AFTER=$(external_monitor_present)

# MARK: a copy of the app that appeared meanwhile

# The pre-run check above refuses to start while a copy out of /Applications is open, so one that
# is running now started during the run: the person's own launch, or whatever launches it (PG-182,
# four sightings and no sender). Its start time is what `ps` says, and that is the moment to look
# at: about ten seconds of `launchd` and `launchservicesd` around it, saved beside the run's
# evidence once (R-06). The log is read after the fact and cannot be read forward, and a copy that
# started and quit again inside the run is never seen at all - both limits are written into the
# file rather than left to be discovered.
save_launch_log() {
    [ ! -e "$LAUNCH_LOG" ] || return 0
    local pid started window
    pid=$(printf '%s' "$yours" | head -1 | cut -f1)
    [ -n "$pid" ] || return 0
    started=$(ps -o lstart= -p "$pid" 2>/dev/null | sed -E 's/^ +//; s/ +$//' || true)
    if ! window=$(log_window_around "$started"); then
        printf 'uitests: non riesco a leggere l'"'"'ora di avvio della copia installata (PID %s), nessun log di lancio salvato\n' "$pid"
        return 0
    fi
    {
        printf 'Copia installata comparsa durante il giro: PID %s, avviata %s.\n' "$pid" "$started"
        printf 'Finestra letta: %s (launchd e launchservicesd). Il log non si legge in avanti,\n' "${window/|/ -> }"
        printf 'e una copia partita e chiusa dentro il giro non si vede mai.\n\n'
        /usr/bin/log show --start "${window%|*}" --end "${window#*|}" --style compact \
            --predicate 'process == "launchd" OR process == "launchservicesd"' 2>&1 || true
    } >"$LAUNCH_LOG"
    printf 'uitests: una copia installata è partita durante il giro, il suo log di lancio è in %s\n' "$LAUNCH_LOG"
}

INSTALLED_APPEARED=0
partition_instances
if [ -n "$yours" ]; then
    INSTALLED_APPEARED=1
    save_launch_log
fi

# MARK: what failed, and whether it is real

printf '\n'
grep -E "^	 Executed [0-9]+ tests?" "$LOG" | tail -1 || true

failures=$(grep -E "^Test Case .* failed \(" "$LOG" || true)

real=""
[ -z "$failures" ] || real="$failures
"

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

# MARK: rerun

# Reds and at least one signal rerun only the tests that failed, once (R-03). It replaces the
# narrower rule this script used to have, which reran only a launch that never happened (PG-181):
# that launch is one of the four signals now, so every such run reaches this function, and the
# tests that failed for a real reason are rerun beside it and either fail again with nothing
# disturbing them, which is a red, or do not.
#
# It sets the four RERUN_ variables `settle_verdict` reads. An installed copy running during the
# rerun counts as a signal whether or not it was there before it: it holds the global hot key, and
# a run beside it is not one to trust.
real_rerun() {
    local sel arg rerun_result installed=0 monitor_now
    local rerun_selection=()
    sel=$(failed_selection "$LOG")
    if [ -z "$sel" ]; then
        # No test is named, so there is nothing to rerun. Without a selection xcodebuild would run
        # the whole suite and call it a rerun of the failures.
        printf 'uitests: nessun test fallito da nominare, non c'"'"'è niente da rilanciare\n'
        return 0
    fi
    while IFS= read -r arg; do rerun_selection+=("$arg"); done <<< "$sel"
    printf '\nuitests: rossi con dei segnali (%s): rilancio una volta solo i %d test falliti\n' \
        "$VERDICT_REASONS" "${#rerun_selection[@]}"
    partition_instances
    close_debris "uitests: istanze rimaste dal primo giro, le chiudo:"

    focus_pergamenum "$FOCUS_LOG.rerun" &
    rerun_focus=$!
    set +e
    xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED_DATA" \
        -resultBundlePath "${RESULT_BUNDLE%.xcresult}-rerun.xcresult" \
        "${rerun_selection[@]}" \
        test >"$LOG.rerun" 2>&1
    rerun_result=$?
    set -e
    kill "$rerun_focus" 2>/dev/null || true

    monitor_now=$(external_monitor_present)
    partition_instances
    if [ -n "$yours" ]; then
        installed=1
        save_launch_log
    fi
    RERUN_EXECUTED=$(count_executed "$LOG.rerun")
    RERUN_REDS=$(reds_from "$LOG.rerun" "$rerun_result")
    # One test per selection line, so a rerun that ran fewer than it was given stopped partway.
    if [ "$RERUN_EXECUTED" -ge "${#rerun_selection[@]}" ]; then
        RERUN_COVERED=1
    fi
    RERUN_SIGNALS=$(collect_signals "$LOG.rerun" "$FOCUS_LOG.rerun" "$installed" "$MON_AFTER" "$monitor_now")
    printf 'uitests: rilancio finito, %s test eseguiti, %s rossi, segnali: %s. Log in %s\n' \
        "$RERUN_EXECUTED" "$RERUN_REDS" "${RERUN_SIGNALS:-nessuno}" "$LOG.rerun"
}

# MARK: verdict

EXECUTED=$(count_executed "$LOG")
REDS=$(reds_from "$LOG" "$RESULT")
SIGNALS=$(collect_signals "$LOG" "$FOCUS_LOG" "$INSTALLED_APPEARED" "$MON_BEFORE" "$MON_AFTER")

# Not in a subshell: the rerun's output is the run's, and the RERUN_ variables it sets have to
# reach `settle_verdict`.
settle_verdict "$EXECUTED" "$REDS" "$SIGNALS"

case "$VERDICT_RESULT" in
    green)
        # Said out loud rather than left to be inferred from a count: the whole point of this
        # script is that the state of the suite stops being something somebody has to work out.
        if [ "$REDS" -eq 0 ]; then
            printf '\nuitests: verde.\n'
        else
            printf '\nuitests: verde al rilancio: i test rossi del primo giro sono passati al secondo tentativo.\n'
        fi ;;
    red) printf '\nuitests: rosso.\n' ;;
    contaminated)
        printf '\nuitests: contaminato (%s): né verde né rosso, la macchina ha disturbato il giro. Da solo non blocca un merge.\n' \
            "$VERDICT_REASONS" ;;
    error)
        printf '\nuitests: nessun test eseguito: è un errore, non un rosso. Nessun verdetto registrato, quello già presente resta.\n' ;;
esac
if [ "$VERDICT_RESULT" != error ] && [ -n "$VERDICT_REASONS" ] && [ "$VERDICT_RESULT" != contaminated ]; then
    printf 'uitests: segnali visti durante il giro: %s\n' "$VERDICT_REASONS"
fi

# Recorded for every session, once the run is settled (the rerun included). Never for a tree that
# was dirty at the start or is now, or that moved meanwhile: that verdict would describe no commit.
# Never for a run that executed no test either, whatever the tree: `write_verdict` refuses it.
record_verdict() {
    if [ "$START_CLEAN" -ne 1 ] || ! is_clean || [ "$(tree_of HEAD)" != "$START_TREE" ]; then
        printf '\nuitests: albero con modifiche non committate o cambiato durante il giro, nessun verdetto registrato\n'
        return 0
    fi
    if ! write_verdict "$START_TREE" "$(git rev-parse HEAD)" "$(date '+%Y-%m-%d %H:%M')" "$SCOPE" \
        "$VERDICT_RESULT" "$EXECUTED" "$VERDICT_REASONS" "${selection[*]}" "$RESULT_BUNDLE" "$LOG"; then
        return 0
    fi
    printf '\nuitests: verdetto %s (%s) registrato per l'"'"'albero %s: lo vedono tutte le sessioni con --status\n' \
        "$VERDICT_RESULT" "$SCOPE" "${START_TREE:0:7}"
}
record_verdict

# MARK: leave nothing behind

# Only the debris. A copy out of /Applications that appeared while the run was going is the
# person's, launched after the pre-run check had passed, and closing it here is the one thing
# that check exists to refuse. It is reported, not touched.
partition_instances
close_debris "
uitests: istanze sopravvissute al giro, le chiudo:"
if [ -n "$yours" ]; then
    printf '\nuitests: una copia installata di Pergamenum è partita durante il giro, la lascio aperta:\n%s\n' "$yours"
fi

for focus_file in "$FOCUS_LOG" "$FOCUS_LOG.rerun"; do
    if [ -s "$focus_file" ]; then
        printf '\nuitests: il focus è stato di un altro %d volte (dettaglio in %s):\n' \
            "$(wc -l <"$focus_file" | tr -d ' ')" "$focus_file"
        awk '{ $1=""; print }' "$focus_file" | sort | uniq -c | sort -rn | sed 's/^/  /'
    fi
done

printf '\nuitests: log completo in %s\n' "$LOG"
printf 'uitests: risultato in %s\n' "$RESULT_BUNDLE"
printf 'uitests: per diagnosticare senza rilanciare: xcrun xcresulttool get test-results summary --path %s\n' "$RESULT_BUNDLE"
exit "$(exit_code_for "$VERDICT_RESULT")"
