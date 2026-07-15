#!/usr/bin/env bash
# tests/test_orchestrator_autonomy.sh — protects the orchestrator from
# bouncing runnable commands or already-settled decisions back to the human.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
PASS=0
FAIL=0

expect_grep() { # $1 fixed text, $2 label
  if grep -qF -- "$1" "$ROOT/agents/orchestrator.md"; then
    PASS=$((PASS + 1)); echo "PASS: $2"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $2 — not found: $1"
  fi
}

expect_absent() { # $1 fixed text, $2 label
  if grep -qF -- "$1" "$ROOT/agents/orchestrator.md"; then
    FAIL=$((FAIL + 1)); echo "FAIL: $2 — forbidden text present: $1"
  else
    PASS=$((PASS + 1)); echo "PASS: $2"
  fi
}

expect_absent "if the action is faster from the human's own shell" \
  "trivial work has no human-shell delegation loophole"
expect_grep "never hand the human a command to run" \
  "runnable commands stay with the workforce"
expect_grep 'arbitrary shell work goes to the **executor**' \
  "unowned commands have an explicit specialist route"
expect_grep "dispatch the executor or domain specialist to start it and keep the session open" \
  "interactive commands start inside a specialist dispatch"
expect_grep "Ask only for the irreducible human action" \
  "interactive assistance is limited to the human-only step"
expect_grep "check it against the original request, the findings ledger, approved artifacts, and specialist evidence" \
  "questions are screened against already-established intent and evidence"
expect_grep "The user's stated outcome is settled intent, not an open preference" \
  "the orchestrator does not ask the user to repeat the requested behavior"
expect_grep "cause, regression proof, and restoration of affected in-scope work" \
  "confirmed incidents carry their necessary remediation scope"
expect_grep "asks permission to execute the settled remedy" \
  "authority gates do not reopen settled scope or behavior"

if grep -qF -- 'test_orchestrator_autonomy.sh' "$ROOT/install.sh"; then
  PASS=$((PASS + 1)); echo "PASS: installer runs the autonomy regression"
else
  FAIL=$((FAIL + 1)); echo "FAIL: installer runs the autonomy regression — test not found in install.sh"
fi

printf 'orchestrator-autonomy tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
