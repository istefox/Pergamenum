#!/usr/bin/env bash
#
# The unit-test command the Stop hook runs (`.claude/test-cmd`): one run at a time on this
# machine, and only the suites the change can reach.
#
# Why it exists. Every session's Stop hook used to run the whole `PergamenumTests` bundle
# (about 7,100 tests, four to eight minutes on its own) under a 600 s ceiling, with nothing
# between sessions. With two or three worktrees ending a turn together, each build and run
# starved the others, every one of them hit the ceiling, and the gate reported a timeout
# (exit 124) that was no test's fault - the state directory showed little else from
# 2026-09-29 on, in bursts of two to four sessions within the same minutes. The full suite
# already runs on every PR in CI, on GitHub's machines; running it again in every session at
# every turn bought nothing but the contention.
#
# What it does:
#
#   - **A machine-wide lock** around the xcodebuild invocation, a directory under
#     ~/Library/Caches holding the owner's pid and checkout. A second session waits for it
#     rather than competing, and says whose run it is waiting on. A lock whose pid is gone
#     (a run killed by the hook's timeout) is taken over, never waited on.
#   - **A selection** of suites from the files this branch changed against `origin/main`,
#     committed or not: the suites declared in a changed test file, and the suites in every
#     test file that names a changed Swift file's stem or one of its top-level types. A change
#     that can reach anything (Project.swift, Tuist/, Resources/, an unknown path) runs the
#     whole bundle. Paths listed in `.claude/test-ignore` are dropped first, with the hook's
#     own matching rules.
#   - **The build is the floor.** `-only-testing` still compiles the app and the whole test
#     target, so a change that breaks compilation anywhere fails here whatever was selected;
#     when nothing is selected the script runs `build-for-testing` alone.
#
# Usage:
#   scripts/gate-tests.sh            the Stop-hook run: selected suites, under the lock
#   scripts/gate-tests.sh --full     the whole bundle, under the lock
#   scripts/gate-tests.sh --dry-run  print the selection and why, run nothing, take no lock
#
# Environment: GATE_LOCK_WAIT (seconds to wait for the lock before failing, default 300, so a wait plus a selected run fits the hook's 600 s ceiling),
# GATE_BASE (the ref to diff against, default origin/main).

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

MODE="selected"
case "${1:-}" in
    --full) MODE="full" ;;
    --dry-run) MODE="dry-run" ;;
    "") ;;
    *) echo "usage: scripts/gate-tests.sh [--full|--dry-run]" >&2; exit 2 ;;
esac

WORKSPACE="Pergamenum.xcworkspace"
TARGET="PergamenumTests"
LOCK="${HOME}/Library/Caches/it.stefer.pergamenum.gate-tests.lock"
LOCK_WAIT="${GATE_LOCK_WAIT:-300}"
BASE_REF="${GATE_BASE:-origin/main}"

if [ ! -e "${WORKSPACE}" ]; then
    echo "gate-tests: ${ROOT}/${WORKSPACE} does not exist - a missing build artifact, not a failing test." >&2
    echo "Fix: cd ${ROOT} && tuist install && tuist generate --no-open" >&2
    exit 66
fi

# --- Selection ---------------------------------------------------------------------------

# The hook's own matching (~/.claude/hooks/stop-gate.sh, its path predicate): blank and '#' lines skipped, a trailing '/'
# is a directory prefix, and '*' matches '/' too.
ignored() {
    local rel="$1" pat lead
    [ -f .claude/test-ignore ] || return 1
    while IFS= read -r pat || [ -n "${pat}" ]; do
        lead=${pat%%[! 	]*}; pat=${pat#"${lead}"}
        case "${pat}" in ''|'#'*) continue ;; esac
        case "${pat}" in */) pat="${pat}*" ;; esac
        # shellcheck disable=SC2254
        case "${rel}" in ${pat}) return 0 ;; esac
    done < .claude/test-ignore
    return 1
}

# Top-level struct/class/enum/actor names declared in a Swift file, attributes and modifiers
# on the same line allowed. Nested types and extensions are not suites of their own here.
declared_types() {
    grep -E '^(@|(final|public|internal|fileprivate|private) |struct |class |enum |actor )' "$1" 2>/dev/null \
        | grep -oE '(^|[ )])(struct|class|enum|actor) +[A-Za-z_][A-Za-z0-9_]*' \
        | awk '{print $NF}' || true
}

changed_files() {
    local base
    base=$(git merge-base HEAD "${BASE_REF}" 2>/dev/null || git rev-parse HEAD)
    {
        git diff --name-only "${base}"
        git ls-files --others --exclude-standard
    } | sort -u
}

FULL_REASON=""
TEST_FILES=()      # test files whose suites are selected
WHY=()             # one line per changed path, for --dry-run and the log

add_test_file() {
    local f="$1" t
    for t in "${TEST_FILES[@]+"${TEST_FILES[@]}"}"; do [ "${t}" = "${f}" ] && return 0; done
    TEST_FILES+=("${f}")
}

# The test files that name any of the given words. One grep over Tests/ per changed file.
add_referencing() {
    local args=() w f
    for w in "$@"; do args+=(-e "${w}"); done
    [ "${#args[@]}" -gt 0 ] || return 0
    while IFS= read -r f; do add_test_file "${f}"; done < <(grep -rlw --include='*.swift' "${args[@]}" Tests 2>/dev/null || true)
}

if [ "${MODE}" != "full" ]; then
    while IFS= read -r path; do
        [ -n "${path}" ] || continue
        if ignored "${path}"; then WHY+=("ignored   ${path}"); continue; fi
        case "${path}" in
            .claude/*|scripts/gate-tests.sh)
                WHY+=("no tests  ${path}") ;;
            Project.swift|Tuist.swift|Tuist/*|Resources/*|Package.swift|Package.resolved)
                FULL_REASON="${path}"; WHY+=("FULL      ${path}") ;;
            Tests/*.swift|Sources/*.swift)
                stem=$(basename "${path}" .swift); stem=${stem%%+*}
                words=("${stem}")
                if [ -f "${path}" ]; then
                    while IFS= read -r t; do [ -n "${t}" ] && words+=("${t}"); done < <(declared_types "${path}")
                fi
                case "${path}" in Tests/*) [ -f "${path}" ] && add_test_file "${path}" ;; esac
                add_referencing "${words[@]}"
                WHY+=("swift     ${path} (${words[*]})") ;;
            Sources/*)
                # A non-Swift source (a plist, a JSON token file) has no stem to follow.
                FULL_REASON="${path}"; WHY+=("FULL      ${path}") ;;
            *)
                # Anything else a test reads by name (scripts/appcast.py, a fixture) selects the
                # files that mention it; one nothing mentions needs no unit test.
                name=$(basename "${path}")
                before=${#TEST_FILES[@]}
                while IFS= read -r f; do add_test_file "${f}"; done < <(grep -rlF --include='*.swift' "${name}" Tests 2>/dev/null || true)
                WHY+=("by name   ${path} ($(( ${#TEST_FILES[@]} - before )) new file(s))") ;;
        esac
    done < <(changed_files)
    [ -n "${FULL_REASON}" ] && MODE_EFFECTIVE="full" || MODE_EFFECTIVE="selected"
else
    MODE_EFFECTIVE="full"
fi

# The `-only-testing` identifiers a test file contributes, one per line: each top-level type and
# each type it extends at top level (a suite's tests may live in an extension), and each top-level
# Swift Testing function. A function is addressed by its full selector - `name()`, `name(_:)`,
# `name(label:)` - because xcodebuild matches the bare name to nothing (checked 2026-10-31, Xcode 27).
# Most of the bundle is top-level functions: 4,354 of about 7,100 tests in 351 files that day.
# A helper type picked up here is harmless: an identifier no test has selects nothing.
test_identifiers() {
    python3 -I - "$1" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
for m in re.finditer(r'^(?:@\w+(?:\([^)\n]*\))?\s+)*(?:(?:final|public|internal|fileprivate|private)\s+)*'
                     r'(?:struct|class|enum|actor|extension)\s+([A-Za-z_]\w*)', src, re.M):
    print(m.group(1))
for m in re.finditer(r'^@Test\b', src, re.M):
    f = re.compile(r'\bfunc\s+([A-Za-z_]\w*)\s*\(').search(src, m.end())
    if not f:
        continue
    i, depth, start, params = f.end(), 1, f.end(), []
    while i < len(src) and depth:
        c = src[i]
        if c in '([': depth += 1
        elif c in ')]': depth -= 1
        if (c == ',' and depth == 1) or depth == 0:
            params.append(src[start:i]); start = i + 1
        i += 1
    labels = []
    for p in params:
        head = p.split(':', 1)[0].split()
        if head and ':' in p:
            labels.append(head[0] + ':')
    print(f.group(1) + '(' + ''.join(labels) + ')')
PY
}

SUITES=()
if [ "${MODE_EFFECTIVE}" = "selected" ]; then
    for f in "${TEST_FILES[@]+"${TEST_FILES[@]}"}"; do
        # Only a file that holds tests contributes identifiers; a fixture file's are not tests.
        grep -qE '@Test|XCTestCase' "${f}" 2>/dev/null || continue
        while IFS= read -r t; do
            [ -n "${t}" ] || continue
            dup=0
            for s in "${SUITES[@]+"${SUITES[@]}"}"; do [ "${s}" = "${t}" ] && dup=1 && break; done
            [ "${dup}" -eq 0 ] && SUITES+=("${t}")
        done < <(test_identifiers "${f}")
    done
fi

if [ "${MODE}" = "dry-run" ]; then
    printf '%s\n' "${WHY[@]+"${WHY[@]}"}"
    if [ "${MODE_EFFECTIVE}" = "full" ]; then
        echo "=> full bundle${FULL_REASON:+ (because of ${FULL_REASON})}"
    elif [ "${#SUITES[@]}" -eq 0 ]; then
        echo "=> build-for-testing only, no suite selected"
    else
        echo "=> ${#SUITES[@]} suite(s) from ${#TEST_FILES[@]} file(s):"
        printf '   %s\n' "${SUITES[@]}"
    fi
    exit 0
fi

# --- Lock --------------------------------------------------------------------------------

CHILD=""
# shellcheck disable=SC2329  # invoked by the EXIT trap below
release() {
    [ -n "${CHILD}" ] && kill "${CHILD}" 2>/dev/null || true
    if [ "$(cat "${LOCK}/pid" 2>/dev/null || true)" = "$$" ]; then
        rm -f "${LOCK}/pid" "${LOCK}/root"
        rmdir "${LOCK}" 2>/dev/null || true
    fi
}
trap release EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

mkdir -p "$(dirname "${LOCK}")"
waited=0
until mkdir "${LOCK}" 2>/dev/null; do
    owner=$(cat "${LOCK}/pid" 2>/dev/null || true)
    if [ -n "${owner}" ] && ! kill -0 "${owner}" 2>/dev/null; then
        echo "gate-tests: taking over a stale lock left by pid ${owner}" >&2
        rm -f "${LOCK}/pid" "${LOCK}/root"; rmdir "${LOCK}" 2>/dev/null || true
        continue
    fi
    # A lock directory with no pid yet is a run between its mkdir and its write: just wait.
    if [ "${waited}" -ge "${LOCK_WAIT}" ]; then
        echo "gate-tests: gave up after ${waited}s waiting for the test lock, held by pid ${owner:-?} in $(cat "${LOCK}/root" 2>/dev/null || echo '?'). Not a test failure: rerun when it is free." >&2
        exit 75
    fi
    if [ $(( waited % 60 )) -eq 0 ]; then
        echo "gate-tests: waiting for the test lock, held by pid ${owner:-?} in $(cat "${LOCK}/root" 2>/dev/null || echo '?') (${waited}s)" >&2
    fi
    sleep 5; waited=$(( waited + 5 ))
done
echo "$$" > "${LOCK}/pid"
echo "${ROOT}" > "${LOCK}/root"

# --- Run ---------------------------------------------------------------------------------

ARGS=(-workspace "${WORKSPACE}" -scheme Pergamenum -destination 'platform=macOS')
if [ "${MODE_EFFECTIVE}" = "full" ]; then
    echo "gate-tests: full ${TARGET}${FULL_REASON:+ (because of ${FULL_REASON})}"
    ARGS+=("-only-testing:${TARGET}" test)
elif [ "${#SUITES[@]}" -eq 0 ]; then
    echo "gate-tests: no suite reaches this change, build-for-testing only"
    ARGS+=(build-for-testing)
else
    echo "gate-tests: ${#SUITES[@]} suite(s) from ${#TEST_FILES[@]} test file(s)"
    for s in "${SUITES[@]}"; do ARGS+=("-only-testing:${TARGET}/${s}"); done
    ARGS+=(test)
fi

xcodebuild "${ARGS[@]}" &
CHILD=$!
set +e
wait "${CHILD}"
rc=$?
set -e
CHILD=""
exit "${rc}"
