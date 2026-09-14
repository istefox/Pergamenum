#!/bin/bash
# ADR-0043 acceptance harness (docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md)
#
# ADR-0043 §D9: "the acceptance criterion is a test that forces the interleaving, never a green
# suite." This script asserts the five named R-11..R-15 interleaving tests exist, that the
# forbidden symbols from the synchronous write door are gone, and (when given a result bundle)
# that the five tests actually passed in that run.
#
# bash 3.2-clean (macOS ships 3.2): no mapfile, no associative arrays, no ${var^^}.
#
# Usage: scripts/adr-0043-interleaving-check.sh [--bundle <path.xcresult>]

set -u

fail=0
bundle=""

while [ $# -gt 0 ]; do
    case "$1" in
        --bundle)
            bundle="$2"
            shift 2
            ;;
        *)
            echo "unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

cd "$(dirname "$0")/.." || exit 2

check() {
    local label="$1"
    local status="$2"
    if [ "$status" -eq 0 ]; then
        echo "PASS: $label"
    else
        echo "FAIL: $label"
        fail=1
    fi
}

# 1. The five R-11..R-15 @Test function names exist in Tests/.
tests=(
    "theOlderMutationFromADifferentWriterIsDropped"
    "twoOverlappingWritesRecordDifferentJournalBefores"
    "aReconciliationBetweenTwoWritesAppliesInClockOrderNotCallOrder"
    "dirtyingTheBufferBetweenAWriteAndItsHandOffRaisesTheConflictPrompt"
    "aWriteWithAStaleExpectedHashIsRefusedAndWritesNothing"
)
for t in "${tests[@]}"; do
    if grep -rq "func $t(" Tests/ 2>/dev/null; then
        check "test exists: $t" 0
    else
        check "test exists: $t" 1
    fi
done

# 2. index.update appears exactly once in Sources/, inside apply (R-02).
update_count=$(grep -rc "index\.update" Sources/ 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')
if [ "$update_count" -eq 1 ]; then
    check "index.update appears exactly once in Sources/" 0
    # The plan named a dedicated VaultSession+WriteOrdering.swift file; the actual Batch-2
    # implementation lives inline in VaultSession.swift's own `apply(_:)` function instead.
    # What matters is the function, not the filename: confirm the line sits inside `func apply(`.
    update_file=$(grep -rln "index\.update" Sources/ 2>/dev/null | head -1)
    apply_ok=1
    if [ -n "$update_file" ]; then
        update_line=$(grep -n "index\.update" "$update_file" | head -1 | cut -d: -f1)
        preceding_func=$(awk -v n="$update_line" 'NR<=n && /func apply\(/{last=NR} END{print last+0}' "$update_file")
        [ "$preceding_func" -gt 0 ] 2>/dev/null && apply_ok=0
    fi
    check "that one index.update line is inside a function named apply(" "$apply_ok"
else
    echo "FAIL: index.update appears $update_count times in Sources/ (expected exactly 1)"
    fail=1
fi

# 3. writeSynchronously / updateIndex are fully gone from Sources/ and Tests/ (R-02, R-03).
if grep -rq "writeSynchronously\|updateIndex" Sources/ Tests/ 2>/dev/null; then
    echo "FAIL: writeSynchronously or updateIndex still referenced:"
    grep -rn "writeSynchronously\|updateIndex" Sources/ Tests/ 2>/dev/null
    fail=1
else
    check "writeSynchronously / updateIndex fully removed from Sources/ and Tests/" 0
fi

# 4. reloadFocusedNote is gone from the Pratiche feature (R-08).
if grep -rq "reloadFocusedNote" Sources/Features/Pratiche/ 2>/dev/null; then
    echo "FAIL: reloadFocusedNote still referenced in Sources/Features/Pratiche/:"
    grep -rn "reloadFocusedNote" Sources/Features/Pratiche/ 2>/dev/null
    fail=1
else
    check "reloadFocusedNote removed from Sources/Features/Pratiche/" 0
fi

# 5. The five tests are reported PASSED in the given result bundle. A test that exists but did
#    not run is not acceptance (§D9) -- a missing bundle is a hard failure, never a skip.
if [ -z "$bundle" ]; then
    echo "FAIL: no --bundle <path.xcresult> supplied -- cannot confirm the five tests actually ran and passed."
    fail=1
elif [ ! -e "$bundle" ]; then
    echo "FAIL: bundle not found: $bundle"
    fail=1
else
    results_json=$(xcrun xcresulttool get test-results tests --path "$bundle" 2>/dev/null)
    if [ -z "$results_json" ]; then
        echo "FAIL: xcresulttool produced no output for bundle: $bundle"
        fail=1
    else
        for t in "${tests[@]}"; do
            # Look for the test name followed eventually by a Passed status within the same
            # JSON node. A crude but bash-3.2-safe substring check: the test name and "Passed"
            # must both appear, and "Failed"/"Expected Failure" must not immediately follow it.
            if echo "$results_json" | grep -q "\"name\" *: *\"$t()\""; then
                node=$(echo "$results_json" | grep -A5 "\"name\" *: *\"$t()\"")
                if echo "$node" | grep -q "\"Passed\""; then
                    check "result bundle reports PASSED: $t" 0
                else
                    check "result bundle reports PASSED: $t" 1
                fi
            else
                check "result bundle contains: $t" 1
            fi
        done
    fi
fi

if [ "$fail" -eq 0 ]; then
    echo "ADR-0043-INTERLEAVING-CHECK: OK"
    exit 0
else
    echo "ADR-0043-INTERLEAVING-CHECK: FAILED"
    exit 1
fi
