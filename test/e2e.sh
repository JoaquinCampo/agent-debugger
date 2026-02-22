#!/usr/bin/env bash
# End-to-end test suite for agent-debugger
# Tests all commands against multiple complex fixtures
set -uo pipefail

BIN="/Users/joaquincamponario/Documents/Personal/agent-debugger/bin/agent-debugger"
FIXTURES="/Users/joaquincamponario/Documents/Personal/agent-debugger/test/fixtures"
PYTHON="/Users/joaquincamponario/Documents/Personal/debugger-tool/.venv/bin/python"

PASS=0
FAIL=0
ERRORS=""

run_cmd() {
    # Run a command, always succeed (capture exit code but don't abort)
    "$@" 2>&1 || true
}

assert_contains() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"

    if echo "$actual" | grep -qF "$expected"; then
        PASS=$((PASS + 1))
        echo "  ✓ $test_name"
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: $test_name\n    Expected to contain: $expected\n    Got: $(echo "$actual" | head -3)\n"
        echo "  ✗ $test_name"
    fi
}

assert_matches() {
    local test_name="$1"
    local pattern="$2"
    local actual="$3"

    if echo "$actual" | grep -qE "$pattern"; then
        PASS=$((PASS + 1))
        echo "  ✓ $test_name"
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: $test_name\n    Expected to match: $pattern\n    Got: $(echo "$actual" | head -3)\n"
        echo "  ✗ $test_name"
    fi
}

cleanup() {
    run_cmd $BIN close >/dev/null
    if [ -f ~/.agent-debugger/daemon.pid ]; then
        kill "$(cat ~/.agent-debugger/daemon.pid)" 2>/dev/null || true
    fi
    rm -f ~/.agent-debugger/daemon.sock ~/.agent-debugger/daemon.pid 2>/dev/null || true
    sleep 0.5
}

# ═══════════════════════════════════════════════════
echo "═══ Test Suite: agent-debugger E2E ═══"
echo ""

# ─── Test 1: Help output ───
echo "─── Test 1: CLI Help ───"
OUT=$(run_cmd $BIN --help)
assert_contains "help shows usage" "agent-debugger" "$OUT"
assert_contains "help shows start command" "start <script>" "$OUT"
assert_contains "help shows eval command" "eval <expression>" "$OUT"

# ─── Test 2: Error handling ───
echo "─── Test 2: Error Handling ───"
cleanup

OUT=$(run_cmd $BIN start)
assert_contains "start without script shows error" "Error" "$OUT"

OUT=$(run_cmd $BIN foobar)
assert_contains "unknown command shows error" "Unknown command" "$OUT"

cleanup
OUT=$(run_cmd $BIN vars)
assert_contains "vars before session shows error" "Error" "$OUT"

cleanup
OUT=$(run_cmd $BIN eval "1+1")
assert_contains "eval before session shows error" "Error" "$OUT"

# ─── Test 3: Recursive tree bug ───
echo "─── Test 3: Recursive Bug ───"
cleanup

OUT=$(run_cmd $BIN start "$FIXTURES/recursive_bug.py" \
    --break "$FIXTURES/recursive_bug.py:18" \
    --python "$PYTHON")
assert_contains "recursive: starts and pauses" "paused" "$OUT"
assert_contains "recursive: hits breakpoint" "max_depth" "$OUT"

OUT=$(run_cmd $BIN vars)
assert_contains "recursive: sees current_depth" "current_depth" "$OUT"

OUT=$(run_cmd $BIN eval "current_depth")
assert_matches "recursive: current_depth is int" "[0-9]" "$OUT"

OUT=$(run_cmd $BIN step)
assert_contains "recursive: step works" "paused" "$OUT"

OUT=$(run_cmd $BIN stack)
assert_contains "recursive: stack shows recursion" "max_depth" "$OUT"

OUT=$(run_cmd $BIN source)
assert_contains "recursive: source shows code" "│" "$OUT"

OUT=$(run_cmd $BIN continue)
assert_matches "recursive: continue works" "paused|terminated" "$OUT"

run_cmd $BIN close >/dev/null

# ─── Test 4: Data pipeline ───
echo "─── Test 4: Data Pipeline ───"
cleanup

# Line 60: records = load_records() — inside main()
OUT=$(run_cmd $BIN start "$FIXTURES/async_pipeline.py" \
    --break "$FIXTURES/async_pipeline.py:60" \
    --python "$PYTHON")
assert_contains "pipeline: starts" "paused" "$OUT"

OUT=$(run_cmd $BIN vars)
assert_contains "pipeline: sees records or is in main" "main" "$OUT"

# Step past the load_records call
OUT=$(run_cmd $BIN step)
assert_contains "pipeline: step past load" "paused" "$OUT"

OUT=$(run_cmd $BIN eval "len(records)")
assert_contains "pipeline: eval len is 7" "7" "$OUT"

OUT=$(run_cmd $BIN eval "type(records[1]['quantity'])")
assert_contains "pipeline: detects type bug (str quantity)" "str" "$OUT"

OUT=$(run_cmd $BIN eval "records[1]['quantity']")
assert_contains "pipeline: string quantity value" "5" "$OUT"

OUT=$(run_cmd $BIN status)
assert_contains "pipeline: status shows paused" "paused" "$OUT"

OUT=$(run_cmd $BIN continue)
assert_matches "pipeline: continue succeeds" "paused|terminated" "$OUT"

run_cmd $BIN close >/dev/null

# ─── Test 5: Class inheritance ───
echo "─── Test 5: Class Inheritance ───"
cleanup

# Line 47: transformed = self.transform_fn(event) — inside TransformingProcessor.process
OUT=$(run_cmd $BIN start "$FIXTURES/class_inheritance.py" \
    --break "$FIXTURES/class_inheritance.py:47" \
    --python "$PYTHON")
assert_contains "inheritance: starts" "paused" "$OUT"

OUT=$(run_cmd $BIN vars)
assert_contains "inheritance: sees self" "self" "$OUT"
assert_contains "inheritance: sees event" "event" "$OUT"

OUT=$(run_cmd $BIN eval "event")
assert_contains "inheritance: eval event has click" "click" "$OUT"

OUT=$(run_cmd $BIN eval "self.allowed_types")
assert_contains "inheritance: allowed_types has click" "click" "$OUT"

OUT=$(run_cmd $BIN step)
assert_contains "inheritance: step" "paused" "$OUT"

OUT=$(run_cmd $BIN stack)
assert_contains "inheritance: stack shows process" "process" "$OUT"

run_cmd $BIN close >/dev/null

# ─── Test 6: Closure bug ───
echo "─── Test 6: Closure Bug ───"
cleanup

OUT=$(run_cmd $BIN start "$FIXTURES/closure_bug.py" \
    --break "$FIXTURES/closure_bug.py:14" \
    --python "$PYTHON")
assert_contains "closure: starts" "paused" "$OUT"

OUT=$(run_cmd $BIN vars)
assert_contains "closure: sees multipliers" "multipliers" "$OUT"
assert_contains "closure: sees i" " i " "$OUT"

OUT=$(run_cmd $BIN eval "i")
assert_contains "closure: i is 0" "0" "$OUT"

OUT=$(run_cmd $BIN continue)
assert_contains "closure: hits bp again" "paused" "$OUT"

OUT=$(run_cmd $BIN eval "i")
assert_contains "closure: i incremented to 1" "1" "$OUT"

OUT=$(run_cmd $BIN eval "len(multipliers)")
assert_contains "closure: multipliers growing" "1" "$OUT"

run_cmd $BIN close >/dev/null

# ─── Test 7: Concurrent state ───
echo "─── Test 7: Concurrent State ───"
cleanup

# Line 92: can_transfer_1 = alice.balance >= 75 — inside simulate_race_condition
OUT=$(run_cmd $BIN start "$FIXTURES/concurrent_state.py" \
    --break "$FIXTURES/concurrent_state.py:92" \
    --python "$PYTHON")
assert_contains "concurrent: starts" "paused" "$OUT"

OUT=$(run_cmd $BIN vars)
assert_contains "concurrent: sees alice" "alice" "$OUT"
assert_contains "concurrent: sees bob" "bob" "$OUT"

OUT=$(run_cmd $BIN eval "alice.balance")
assert_contains "concurrent: alice starts at 100" "100" "$OUT"

OUT=$(run_cmd $BIN eval "bob.balance")
assert_contains "concurrent: bob starts at 50" "50" "$OUT"

OUT=$(run_cmd $BIN step)
assert_contains "concurrent: step" "paused" "$OUT"

OUT=$(run_cmd $BIN eval "can_transfer_1")
assert_contains "concurrent: transfer check is True" "True" "$OUT"

run_cmd $BIN close >/dev/null

# ─── Test 8: Multiple breakpoints ───
echo "─── Test 8: Multiple Breakpoints ───"
cleanup

OUT=$(run_cmd $BIN start "$FIXTURES/buggy_script.py" \
    --break "$FIXTURES/buggy_script.py:23" \
    --break "$FIXTURES/buggy_script.py:26" \
    --python "$PYTHON")
assert_contains "multi-bp: starts paused" "paused" "$OUT"

# Continue to next breakpoint
OUT=$(run_cmd $BIN continue)
assert_contains "multi-bp: hits second breakpoint" "paused" "$OUT"

OUT=$(run_cmd $BIN source)
assert_contains "multi-bp: source shows code" "│" "$OUT"

run_cmd $BIN close >/dev/null

# ─── Test 9: Conditional breakpoint ───
echo "─── Test 9: Conditional Breakpoint ───"
cleanup

OUT=$(run_cmd $BIN start "$FIXTURES/closure_bug.py" \
    --break "$FIXTURES/closure_bug.py:14:i == 3" \
    --python "$PYTHON")
assert_contains "conditional: starts" "paused" "$OUT"

OUT=$(run_cmd $BIN eval "i")
assert_contains "conditional: i is 3" "3" "$OUT"

run_cmd $BIN close >/dev/null

# ─── Test 10: Step out ───
echo "─── Test 10: Step Out ───"
cleanup

OUT=$(run_cmd $BIN start "$FIXTURES/recursive_bug.py" \
    --break "$FIXTURES/recursive_bug.py:22" \
    --python "$PYTHON")
assert_contains "step-out: starts" "paused" "$OUT"

# Step into
OUT=$(run_cmd $BIN step into)
assert_contains "step-out: step into" "paused" "$OUT"

# Step out
OUT=$(run_cmd $BIN step out)
assert_contains "step-out: step out" "paused" "$OUT"

run_cmd $BIN close >/dev/null

# ─── Test 11: Run to termination ───
echo "─── Test 11: Run to Termination ───"
cleanup

# Use closure_bug which runs to completion without crashing
# Break at line 48 (print results) which runs only once, then continue to let it finish
OUT=$(run_cmd $BIN start "$FIXTURES/closure_bug.py" \
    --break "$FIXTURES/closure_bug.py:62" \
    --python "$PYTHON")
assert_contains "terminate: starts" "paused" "$OUT"

# Continue past — the program has no more breakpoints and will finish
OUT=$(run_cmd $BIN continue)
assert_matches "terminate: program ended" "terminated" "$OUT"

# Vars after termination should error
OUT=$(run_cmd $BIN vars)
assert_contains "terminate: vars after end errors" "Error" "$OUT"

run_cmd $BIN close >/dev/null

# ─── Test 12: Add breakpoint mid-session ───
echo "─── Test 12: Add Breakpoint Mid-Session ───"
cleanup

# Break in closure_bug at the start of main, then add another breakpoint further down
OUT=$(run_cmd $BIN start "$FIXTURES/closure_bug.py" \
    --break "$FIXTURES/closure_bug.py:39" \
    --python "$PYTHON")
assert_contains "add-bp: starts" "paused" "$OUT"

# Add a new breakpoint at line 54 (second print)
OUT=$(run_cmd $BIN break "$FIXTURES/closure_bug.py:54")
assert_contains "add-bp: breakpoint set" "Breakpoint" "$OUT"

# Continue — should hit the added breakpoint
OUT=$(run_cmd $BIN continue)
assert_contains "add-bp: continue after add" "paused" "$OUT"

run_cmd $BIN close >/dev/null

# ─── Test 13: Session lifecycle ───
echo "─── Test 13: Session Lifecycle ───"
cleanup

OUT=$(run_cmd $BIN start "$FIXTURES/buggy_script.py" \
    --break "$FIXTURES/buggy_script.py:26" \
    --python "$PYTHON")
assert_contains "lifecycle: first start" "paused" "$OUT"

# Double start should fail
OUT=$(run_cmd $BIN start "$FIXTURES/buggy_script.py" \
    --break "$FIXTURES/buggy_script.py:26" \
    --python "$PYTHON")
assert_contains "lifecycle: double start errors" "Error" "$OUT"

# Close
OUT=$(run_cmd $BIN close)
assert_contains "lifecycle: close works" "closed" "$OUT"

# Need to wait for daemon to actually shutdown and restart fresh
cleanup

# Start again after close
OUT=$(run_cmd $BIN start "$FIXTURES/buggy_script.py" \
    --break "$FIXTURES/buggy_script.py:26" \
    --python "$PYTHON")
assert_contains "lifecycle: restart after close" "paused" "$OUT"

run_cmd $BIN close >/dev/null

# ─── Test 14: Original buggy_script full debug workflow ───
echo "─── Test 14: Full Debug Workflow ───"
cleanup

# Break at line 25 (total += data["age"]) to see the data before it does the add
OUT=$(run_cmd $BIN start "$FIXTURES/buggy_script.py" \
    --break "$FIXTURES/buggy_script.py:25" \
    --python "$PYTHON")
assert_contains "workflow: starts at breakpoint" "paused" "$OUT"
assert_contains "workflow: in calculate_average_age" "calculate_average_age" "$OUT"

OUT=$(run_cmd $BIN vars)
assert_contains "workflow: sees total" "total" "$OUT"
assert_contains "workflow: sees data" "data" "$OUT"

OUT=$(run_cmd $BIN eval "data['name']")
assert_contains "workflow: first user Alice" "Alice" "$OUT"

# Continue to next iteration (Bob)
OUT=$(run_cmd $BIN continue)
assert_contains "workflow: continue to Bob" "paused" "$OUT"

OUT=$(run_cmd $BIN eval "data['name']")
assert_contains "workflow: Bob iteration" "Bob" "$OUT"

# Continue to Charlie (string age bug)
OUT=$(run_cmd $BIN continue)
assert_contains "workflow: continue to Charlie" "paused" "$OUT"

OUT=$(run_cmd $BIN eval "data['name']")
assert_contains "workflow: Charlie iteration" "Charlie" "$OUT"

OUT=$(run_cmd $BIN eval "type(data['age'])")
assert_contains "workflow: Charlie age is string!" "str" "$OUT"

OUT=$(run_cmd $BIN eval "data['age']")
assert_contains "workflow: age value is 35" "35" "$OUT"

# This continue will crash: total (int 55) + "35" (str) = TypeError
OUT=$(run_cmd $BIN continue)
assert_matches "workflow: program crashes on type error" "terminated|paused" "$OUT"

run_cmd $BIN close >/dev/null

# ─── Test 15: Node.js / js-debug (gated on js-debug availability) ───
# Check if js-debug is available before running Node tests
JS_DEBUG_AVAILABLE=0
JS_DEBUG_DIR="$HOME/.vscode/extensions"
if [ -n "${JS_DEBUG_PATH:-}" ]; then
    JS_DEBUG_AVAILABLE=1
elif [ -d "$JS_DEBUG_DIR" ]; then
    JS_DEBUG_MATCH=$(ls -d "$JS_DEBUG_DIR"/ms-vscode.js-debug-*/src/dapDebugServer.js 2>/dev/null | tail -1)
    if [ -n "$JS_DEBUG_MATCH" ]; then
        JS_DEBUG_AVAILABLE=1
    fi
fi

if [ "$JS_DEBUG_AVAILABLE" -eq 1 ]; then
    echo "─── Test 15: Node.js (js-debug) ───"
    cleanup

    OUT=$(run_cmd $BIN start "$FIXTURES/buggy_script.js" \
        --break "$FIXTURES/buggy_script.js:22")
    assert_contains "node: starts and pauses" "paused" "$OUT"

    OUT=$(run_cmd $BIN vars)
    assert_contains "node: sees total" "total" "$OUT"

    OUT=$(run_cmd $BIN eval "data.name")
    assert_contains "node: eval data.name" "Alice" "$OUT"

    OUT=$(run_cmd $BIN continue)
    assert_contains "node: continue to Bob" "paused" "$OUT"

    OUT=$(run_cmd $BIN eval "data.name")
    assert_contains "node: Bob iteration" "Bob" "$OUT"

    OUT=$(run_cmd $BIN continue)
    assert_contains "node: continue to Charlie" "paused" "$OUT"

    OUT=$(run_cmd $BIN eval "typeof data.age")
    assert_contains "node: detects string age bug" "string" "$OUT"

    run_cmd $BIN close >/dev/null
else
    echo "─── Test 15: Node.js (js-debug) — SKIPPED (js-debug not found) ───"
fi

# ═══════════════════════════════════════════════════
cleanup
echo ""
echo "═══ Results ═══"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "  Total:  $((PASS + FAIL))"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "═══ Failures ═══"
    printf "%b" "$ERRORS"
    exit 1
fi

echo ""
echo "All tests passed!"
