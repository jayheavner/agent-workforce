#!/usr/bin/env bash
# tests/test_completion_lint.sh — regression coverage for the final delivery
# claim gate. A completion claim must have a passing, target-appropriate receipt.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
LINTER="$ROOT/tools/lint_completion_claims.py"
AUDIT="$ROOT/bin/agent-workforce-closeout"
FIXTURES="$HERE/fixtures/completion-lint"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

expect_pass() { # $1 fixture, $2 label
  local output rc
  set +e
  output="$(python3 "$LINTER" --require-receipt "$FIXTURES/$1" 2>&1)"
  rc=$?
  set -u
  if [ "$rc" -eq 0 ] && printf '%s' "$output" | grep -qF 'PASS'; then
    ok
  else
    bad "$2 (rc=$rc; output=$output)"
  fi
}

expect_block() { # $1 fixture, $2 rule, $3 label
  local output rc
  set +e
  output="$(python3 "$LINTER" --require-receipt "$FIXTURES/$1" 2>&1)"
  rc=$?
  set -u
  if [ "$rc" -eq 1 ] && printf '%s' "$output" | grep -qF "BLOCK $2"; then
    ok
  else
    bad "$3 (rc=$rc; output=$output)"
  fi
}

expect_block stopping-short.txt C1 \
  "exact stopping-short transcript cannot claim completion while deployment is unfinished"
expect_pass shippable.md \
  "a deployed-service receipt with all required evidence passes"
expect_pass incomplete.md \
  "an honestly incomplete report remains reportable without a completion claim"
expect_block premature-shippable.md C3 \
  "SHIPPABLE blocks when a required deployment field is pending"
expect_block invalid-na.md C4 \
  "deployed-service cannot mark deployment not applicable"

set +e
CLOSEOUT_JSON="$(bash "$AUDIT" --repo "$ROOT" --format json --completion-report "$FIXTURES/shippable.md" 2>&1)"
CLOSEOUT_RC=$?
INCOMPLETE_CLOSEOUT="$(bash "$AUDIT" --repo "$ROOT" --format json --completion-report "$FIXTURES/incomplete.md" 2>&1)"
INCOMPLETE_RC=$?
set -u
if [ "$CLOSEOUT_RC" -eq 0 ] && printf '%s' "$CLOSEOUT_JSON" | jq -e '.completion_report.delivery_claim_lint == "pass"' >/dev/null 2>&1; then
  ok
else
  bad "closeout records a passing delivery-claim lint result (rc=$CLOSEOUT_RC; output=$CLOSEOUT_JSON)"
fi
if [ "$INCOMPLETE_RC" -ne 0 ] && printf '%s' "$INCOMPLETE_CLOSEOUT" | grep -qF 'completion closeout requires shipment-verdict: SHIPPABLE'; then
  ok
else
  bad "closeout rejects a receipt that is honestly incomplete (rc=$INCOMPLETE_RC; output=$INCOMPLETE_CLOSEOUT)"
fi

printf 'completion-lint tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
