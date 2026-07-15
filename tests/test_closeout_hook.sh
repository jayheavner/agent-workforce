#!/usr/bin/env bash
# tests/test_closeout_hook.sh — behavior and coverage gate for closeout hooks.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
COVERAGE_FILE="$(mktemp)"
export COVERAGE_FILE
trap 'rm -f "$COVERAGE_FILE"' EXIT

python3 -m coverage run --source="$ROOT/hooks" \
  "$HERE/test_agent_team_closeout.py"
RC=$?
[ "$RC" -eq 0 ] || exit "$RC"

python3 -m coverage report --include="$ROOT/hooks/agent_team_closeout.py" --fail-under=90
