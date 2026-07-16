#!/usr/bin/env bash
# Exercise the installed process-assurance hook and enforce its coverage gate.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
HOOK="$ROOT/hooks/agent-team-process-assurance.py"
STATE="$(mktemp -d)"
COVERAGE_FILE="$(mktemp)"
export COVERAGE_FILE
trap 'rm -rf "$STATE"; rm -f "$COVERAGE_FILE"' EXIT

PASS=0
FAIL=0
RC=0

run_hook() { # mode, command, payload
  set +e
  printf '%s' "$3" | AGENT_TEAM_PROCESS_ASSURANCE_MODE="$1" \
    AGENT_TEAM_PROCESS_ASSURANCE_STATE="$STATE" python3 "$HOOK" "$2" >/dev/null 2>&1
  RC=$?
  set -u
}

expect_rc() { # expected, mode, command, payload, label
  run_hook "$2" "$3" "$4"
  if [ "$RC" -eq "$1" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s (expected %s, got %s)\n' "$5" "$1" "$RC"
  fi
}

expect_rc 0 OFF dispatch 'not-json' 'OFF is inert'
expect_rc 2 ENFORCE dispatch \
  "$(jq -cn '{session_id:"no-charter",tool_name:"Agent",tool_input:{subagent_type:"architect",prompt:"Design"}}')" \
  'ENFORCE rejects a session without a charter'

(
  cd "$ROOT" || exit 1
  python3 -m coverage run --source=hooks.process_assurance \
    -m unittest discover -s tests -p 'test_process_assurance.py'
) >/dev/null || {
    printf 'FAIL: process assurance unit tests failed\n'
    exit 1
  }
COVERAGE="$(python3 -m coverage report --format=total)"
if [ "$COVERAGE" -ge 90 ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  printf 'FAIL: process-assurance coverage is %s%%, expected at least 90%%\n' "$COVERAGE"
fi

printf 'process-assurance hook tests: PASS=%s FAIL=%s COVERAGE=%s%%\n' "$PASS" "$FAIL" "$COVERAGE"
[ "$FAIL" -eq 0 ]
