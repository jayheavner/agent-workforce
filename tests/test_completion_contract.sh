#!/usr/bin/env bash
# tests/test_completion_contract.sh — protects the fail-closed meaning of a
# completion claim across the verifier, closeout, and orchestrator contracts.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PASS=0
FAIL=0

expect_grep() { # $1 repo-relative file, $2 fixed text, $3 label
  if [ -f "$ROOT/$1" ] && grep -qF -- "$2" "$ROOT/$1"; then
    PASS=$((PASS + 1)); echo "PASS: $3"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $3 — not found in $1: $2"
  fi
}

expect_grep skills/verifying/SKILL.md "Shipment verdict" \
  "verifying separates shipment from acceptance"
expect_grep skills/verifying/SKILL.md "NOT SHIPPABLE" \
  "verifying makes unresolved release work fail closed"
expect_grep agents/verifier.md "delivery contract" \
  "verifier requires the delivery contract"
expect_grep agents/verifier.md "pre-existing" \
  "verifier treats pre-existing suite failures as release blockers"
expect_grep skills/closeout/SKILL.md "Completion is not a ledger heading" \
  "closeout forbids a completion claim while required work remains"
expect_grep skills/closeout/SKILL.md "delivery target" \
  "closeout requires an explicit delivery target"
expect_grep skills/finishing-a-branch/SKILL.md "NOT SHIPPABLE" \
  "branch finishing blocks completion while required delivery work remains"
expect_grep skills/finishing-a-branch/SKILL.md "For every code change, run the full suite" \
  "branch finishing makes the full suite a shipment requirement"
expect_grep agents/orchestrator.md "after the final code edit" \
  "orchestrator requires fresh verification after repairs"
expect_grep agents/orchestrator.md "Do not call work done, complete, or shippable" \
  "orchestrator reserves completion language for completed delivery"
expect_grep skills/agent-workforce/SKILL.md "Do not call work done, complete, or shippable" \
  "Codex workforce route shares the completion rule"
expect_grep install.sh 'test_completion_contract.sh' \
  "installer runs the completion-contract regression test"
expect_grep agents/orchestrator.md "Executor finalizer" \
  "orchestrator assigns late artifacts to an executor finalizer"
expect_grep agents/orchestrator.md "agent_team_closeout.py\" stop" \
  "snapshot orchestrator registers the blocking Stop hook"
expect_grep agents/verifier.md "WORKFORCE_VERIFICATION:" \
  "verifier emits machine-readable terminal evidence"
expect_grep agents/reviewer.md "WORKFORCE_REVIEW:" \
  "reviewer emits machine-readable terminal evidence"
expect_grep skills/agent-workforce/SKILL.md "Local commits are part of repository delivery" \
  "Codex workforce treats focused local commits as default delivery work"
expect_grep skills/closeout/SKILL.md "finalizer" \
  "closeout assigns a finalizer after late documentation"
expect_grep install.sh 'test_closeout_hook.sh' \
  "installer runs the behavioral closeout-hook regression"
expect_grep agents/orchestrator.md "If integration and cleanup are inside" \
  "orchestrator executes authorized task-created cleanup"
expect_grep agents/executor.md "implementation request as standing authorization" \
  "executor finalizer does not ask for a commit reminder"

printf 'completion-contract tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
