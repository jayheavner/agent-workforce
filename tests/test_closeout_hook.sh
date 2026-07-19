#!/usr/bin/env bash
# tests/test_closeout_hook.sh — behavior and coverage gate for the closeout
# Stop hook. The tests drive the hook as a subprocess (the way the harness
# does), so subprocess runs are measured with coverage's parallel mode and
# combined before reporting. Threshold is 80: the hook has deliberate
# fail-open branches (state I/O errors, cost-report subprocess failures)
# that a behavior test cannot reach without an unreasonable amount of fault
# injection.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
DATA_DIR="$(mktemp -d)"
trap 'rm -rf "$DATA_DIR"' EXIT
export COVERAGE_FILE="$DATA_DIR/.coverage"

COVERAGE_HOOK_SUBPROCESS=1 python3 -m coverage run --parallel-mode \
  --source="$ROOT/hooks" "$HERE/test_agent_team_closeout.py"
RC=$?
[ "$RC" -eq 0 ] || exit "$RC"

python3 -m coverage combine >/dev/null || exit 1
python3 -m coverage report --include="$ROOT/hooks/agent_team_closeout.py" --fail-under=80
