#!/usr/bin/env bash

set -u

HOOK_DIR="${HOME}/.claude/hooks"
LOG_FILE="${HOOK_DIR}/blocked.log"

mkdir -p "$HOOK_DIR"

INPUT="$(cat)"

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
PROJECT_PATH="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"

[ -z "$COMMAND" ] && exit 0
[ -z "$PROJECT_PATH" ] && PROJECT_PATH="$(pwd)"

REASON=""

# rm -rf / rm -fr / rm -r -f / rm -f -r
if printf '%s\n' "$COMMAND" |
    grep -Eiq '(^|[;&|[:space:]])rm([[:space:]]+-[^[:space:]]*)*[[:space:]]+.*'; then

    RM_ARGS="$(printf '%s\n' "$COMMAND" |
        sed -E 's/.*(^|[;&|[:space:]])rm[[:space:]]+//')"

    HAS_RECURSIVE=0
    HAS_FORCE=0

    printf '%s\n' "$RM_ARGS" |
        grep -Eiq '(^|[[:space:]])-[^[:space:]]*r[^[:space:]]*([[:space:]]|$)|--recursive' &&
        HAS_RECURSIVE=1

    printf '%s\n' "$RM_ARGS" |
        grep -Eiq '(^|[[:space:]])-[^[:space:]]*f[^[:space:]]*([[:space:]]|$)|--force' &&
        HAS_FORCE=1

    if [ "$HAS_RECURSIVE" -eq 1 ] && [ "$HAS_FORCE" -eq 1 ]; then
        REASON="Blocked destructive command: rm -rf"
    fi
fi

# git push --force / git push -f
if [ -z "$REASON" ] &&
   printf '%s\n' "$COMMAND" |
   grep -Eiq '(^|[;&|[:space:]])git[[:space:]]+push([^;&|]*)[[:space:]](--force|-f)([[:space:]]|$)'; then
    REASON="Blocked destructive command: git push --force"
fi

# DROP TABLE
if [ -z "$REASON" ] &&
   printf '%s\n' "$COMMAND" |
   grep -Eiq 'DROP[[:space:]]+TABLE'; then
    REASON="Blocked destructive command: DROP TABLE"
fi

# TRUNCATE / TRUNCATE TABLE
if [ -z "$REASON" ] &&
   printf '%s\n' "$COMMAND" |
   grep -Eiq 'TRUNCATE([[:space:]]+TABLE)?'; then
    REASON="Blocked destructive command: TRUNCATE"
fi

# DELETE FROM without WHERE
if [ -z "$REASON" ] &&
   printf '%s\n' "$COMMAND" |
   grep -Eiq 'DELETE[[:space:]]+FROM'; then

    DELETE_PART="$(printf '%s\n' "$COMMAND" |
        sed -n 's/.*[Dd][Ee][Ll][Ee][Tt][Ee][[:space:]]\+[Ff][Rr][Oo][Mm][[:space:]]*\(.*\)/\1/p')"

    if ! printf '%s\n' "$DELETE_PART" |
        grep -Eiq 'WHERE'; then
        REASON="Blocked destructive command: DELETE FROM without WHERE"
    fi
fi

[ -z "$REASON" ] && exit 0

TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

printf '%s\tproject=%s\tcommand=%s\n' \
    "$TIMESTAMP" \
    "$PROJECT_PATH" \
    "$COMMAND" >> "$LOG_FILE"

jq -n \
    --arg reason "$REASON" \
    '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: $reason
        }
    }'

exit 0

