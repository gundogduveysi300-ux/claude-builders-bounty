#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HOOK="$SCRIPT_DIR/destructive_bash_guard.sh"

PASS=0
FAIL=0

TEST_HOME="$(mktemp -d)"
export HOME="$TEST_HOME"

cleanup() {
    rm -rf "$TEST_HOME"
}

trap cleanup EXIT

assert_blocked() {
    local name="$1"
    local command="$2"
    local expected="$3"

    local input
    local output
    local decision

    input="$(jq -n \
        --arg command "$command" \
        --arg cwd "/tmp/test-project" \
        '{
            tool_name: "Bash",
            tool_input: {command: $command},
            cwd: $cwd
        }')"

    output="$(printf '%s' "$input" | "$HOOK")"
    decision="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // empty')"

    if [ "$decision" = "deny" ] &&
       printf '%s' "$output" | grep -Fq "$expected"; then
        printf 'PASS: %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf 'FAIL: %s\n' "$name"
        printf '  Expected: BLOCK / %s\n' "$expected"
        printf '  Got: %s\n' "$output"
        FAIL=$((FAIL + 1))
    fi
}

assert_allowed() {
    local name="$1"
    local command="$2"

    local input
    local output

    input="$(jq -n \
        --arg command "$command" \
        --arg cwd "/tmp/test-project" \
        '{
            tool_name: "Bash",
            tool_input: {command: $command},
            cwd: $cwd
        }')"

    output="$(printf '%s' "$input" | "$HOOK")"

    if [ -z "$output" ]; then
        printf 'PASS: %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf 'FAIL: %s\n' "$name"
        printf '  Expected: ALLOW / empty output\n'
        printf '  Got: %s\n' "$output"
        FAIL=$((FAIL + 1))
    fi
}

printf '%s\n' "=== Destructive command tests ==="

assert_blocked \
    "rm -rf" \
    "rm -rf /tmp/test" \
    "rm -rf"

assert_blocked \
    "rm -fr" \
    "rm -fr /tmp/test" \
    "rm -rf"

assert_blocked \
    "git push --force" \
    "git push --force origin main" \
    "git push --force"

assert_blocked \
    "git push -f" \
    "git push -f origin main" \
    "git push --force"

assert_blocked \
    "DROP TABLE" \
    "DROP TABLE users" \
    "DROP TABLE"

assert_blocked \
    "TRUNCATE TABLE" \
    "TRUNCATE TABLE users" \
    "TRUNCATE"

assert_blocked \
    "TRUNCATE" \
    "TRUNCATE users" \
    "TRUNCATE"

assert_blocked \
    "DELETE FROM without WHERE" \
    "DELETE FROM users" \
    "DELETE FROM without WHERE"

assert_blocked \
    "case-insensitive DROP TABLE" \
    "drop table users" \
    "DROP TABLE"

assert_blocked \
    "quoted command" \
    'echo "hello world" && rm -rf /tmp/test' \
    "rm -rf"

printf '\n%s\n' "=== Safe command tests ==="

assert_allowed \
    "ls" \
    "ls -la"

assert_allowed \
    "git status" \
    "git status"

assert_allowed \
    "normal git push" \
    "git push origin main"

assert_allowed \
    "DELETE with WHERE" \
    "DELETE FROM users WHERE id=1"

assert_allowed \
    "echo" \
    "echo hello"

assert_allowed \
    "npm test" \
    "npm test"

printf '\n%s\n' "=== Result ==="

printf 'Passed: %d\n' "$PASS"
printf 'Failed: %d\n' "$FAIL"

if [ "$FAIL" -eq 0 ]; then
    printf '%s\n' "ALL TESTS PASSED"
    exit 0
fi

printf '%s\n' "TESTS FAILED"
exit 1
