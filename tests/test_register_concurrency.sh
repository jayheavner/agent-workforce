#!/usr/bin/env bash
# tests/test_register_concurrency.sh — twenty real processes race one claim, and
# the filesystem must elect exactly one winner.
#
# This is the test the register exists to pass. It is committed red, before the
# register is written (plan Task 1), so the mechanism is proved against a real race
# rather than against a mock of one.
#
# Safety: AGENT_TEAM_REGISTER_DIR points inside this run's own throwaway fixture,
# so no case can read or write the machine's live register.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/concurrency.sh
. "$HERE/lib/concurrency.sh"

PASSED=0
FAILED=0

WORK="$(mktemp -d "${TMPDIR:-/tmp}/register-concurrency.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

REGDIR="$WORK/register"
PROJ="$WORK/proj"
mkdir -p "$REGDIR" "$PROJ"
chmod 700 "$REGDIR"
export AGENT_TEAM_REGISTER_DIR="$REGDIR"
export AGENT_TEAM_TELEMETRY_DIR="$WORK/telemetry"

git -C "$PROJ" init -q -b main
git -C "$PROJ" config user.email fixture@example.com
git -C "$PROJ" config user.name "Concurrency Fixture"
printf '.claude/worktrees/\n' > "$PROJ/.gitignore"
printf 'x\n' > "$PROJ/file.txt"
git -C "$PROJ" add -A
git -C "$PROJ" commit -qm "init: fixture project"
PROJ="$(cd "$PROJ" && pwd -P)"

OUTDIR="$(spawn_claimants 20 "$REGDIR" "$PROJ" raced)"
if assert_exactly_one_winner "$OUTDIR" 20; then
  PASSED=$((PASSED + 1))
else
  FAILED=$((FAILED + 1))
fi

printf 'passed=%s failed=%s\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
