#!/usr/bin/env bash
# tests/test_orchestrator_autonomy.sh — pins the load-bearing autonomy prose of
# the redesigned orchestrator (autonomy-first redesign, 2026-07-18): commands
# stay with the workforce, standing authorization is consumed exactly once, the
# human is paused only at the enumerated gates, repair loops are bounded, and
# costs are exact, never estimated. The deleted GATE/charter machinery must not
# creep back in.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
ORCH="$ROOT/agents/orchestrator.md"
SKILL="$ROOT/skills/agent-workforce/SKILL.md"
PASS=0
FAIL=0

# Prose in these files hard-wraps (list continuations indent, too), so a
# load-bearing sentence can span physical lines. Flatten all whitespace runs to
# single spaces once per file, then grep the flattened text with fixed strings
# (grep -qF).
FLAT_ORCH="$(tr -s '[:space:]' ' ' < "$ORCH")"
FLAT_SKILL="$(tr -s '[:space:]' ' ' < "$SKILL")"

expect_grep() { # $1 flattened content, $2 fixed text, $3 label
  if printf '%s' "$1" | grep -qF -- "$2"; then
    PASS=$((PASS + 1)); echo "PASS: $3"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $3 — not found: $2"
  fi
}

expect_absent() { # $1 flattened content, $2 fixed text, $3 label
  if printf '%s' "$1" | grep -qF -- "$2"; then
    FAIL=$((FAIL + 1)); echo "FAIL: $3 — forbidden text present: $2"
  else
    PASS=$((PASS + 1)); echo "PASS: $3"
  fi
}

# --- agents/orchestrator.md ---
expect_grep "$FLAT_ORCH" "Never hand the human a command to run" \
  "runnable commands stay with the workforce"
expect_grep "$FLAT_ORCH" "Standing authorization." \
  "the original request is standing authorization"
expect_grep "$FLAT_ORCH" "consumes its gate exactly once" \
  "an explicit choice is consumed exactly once"
expect_grep "$FLAT_ORCH" "Pause for the human only when" \
  "human interruption is limited to the enumerated gates"
expect_grep "$FLAT_ORCH" "Fact-shaped questions are lookups, not questions." \
  "fact-shaped questions become lookups"
expect_grep "$FLAT_ORCH" "A declined question is settled" \
  "declined questions are not re-presented"
expect_grep "$FLAT_ORCH" "at most two repair loops" \
  "repair loops are bounded before escalation"
expect_grep "$FLAT_ORCH" "Never estimate a cost" \
  "cost reporting is exact, never estimated"
expect_grep "$FLAT_ORCH" "resolve \`policy:closeout-integration\`" \
  "integration path is resolved from policy at intake"
expect_grep "$FLAT_ORCH" "treat only an actual denial as a boundary" \
  "permission modes are tested by attempt, not assumption"
expect_grep "$FLAT_ORCH" "aws sso login" \
  "interactive credential logins are launched, not deferred"
expect_absent "$FLAT_ORCH" "→ GATE →" \
  "routes carry no routine phase-boundary gates"
expect_absent "$FLAT_ORCH" "WORKFORCE_CHARTER" \
  "the deleted charter machinery stays gone"

# --- skills/agent-workforce/SKILL.md ---
expect_grep "$FLAT_SKILL" "default is uninterrupted execution" \
  "workforce skill defaults to unattended progress"
expect_grep "$FLAT_SKILL" "consumes that authorization exactly once" \
  "workforce skill consumes explicit approval once"
expect_absent "$FLAT_SKILL" "WORKFORCE_CHARTER" \
  "workforce skill carries no charter machinery"

printf 'orchestrator-autonomy tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
