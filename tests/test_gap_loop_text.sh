#!/usr/bin/env bash
# tests/test_gap_loop_text.sh — verifies the gap-loop normative text landed in the
# agent files and the gap-record schema exists. Presence checks, not drift checks:
# these phrases are load-bearing (sensors, schema fields, disclosure lines) and a
# future edit that drops one silently disables part of the loop.
# Spec: docs/superpowers/specs/2026-07-12-gap-detection-capability-loop-design.md
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE/.."
PASS=0
FAIL=0

expect_grep() { # $1 repo-relative file, $2 fixed string, $3 label
  if [ -f "$ROOT/$1" ] && grep -qF -- "$2" "$ROOT/$1"; then
    PASS=$((PASS+1)); echo "PASS: $3"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $3 — not found in $1: $2"
  fi
}

# --- Task 1: gap-record schema ---
expect_grep docs/gaps/README.md "schema: 1" \
  "gap README declares schema v1"
expect_grep docs/gaps/README.md "kind: domain | fit | permission/tool | process" \
  "gap README lists the four gap kinds"
expect_grep docs/gaps/README.md "does not exist for promotion purposes" \
  "gap README carries the canonical-main rule"
expect_grep docs/gaps/README.md "Declined is not terminal" \
  "gap README carries decline semantics"
expect_grep docs/gaps/README.md "GAP-<YYYYMMDD>-<kind>-<slug>.md" \
  "gap README defines the record filename"

# --- Task 2: architect domain sensor ---
expect_grep agents/architect.md "practitioner test" \
  "architect carries the practitioner test"
expect_grep agents/architect.md "DOMAIN GAP: <field>" \
  "architect declares DOMAIN GAP in reports"
expect_grep agents/architect.md "the plan is the carrier" \
  "architect states plan-as-carrier"
expect_grep agents/architect.md "domain-uncertified" \
  "architect labels uncertified criteria"
expect_grep agents/architect.md "stop-and-report to the orchestrator, never the builder" \
  "architect plans forbid builder domain improvisation"

# --- Task 3: orchestrator gap handling ---
expect_grep agents/orchestrator.md "## Gap flags" \
  "orchestrator has the Gap flags section"
expect_grep agents/orchestrator.md "hard is never a gap" \
  "orchestrator carries the discriminator"
expect_grep agents/orchestrator.md '`gaps: none`' \
  "orchestrator requires the gate gaps line"
expect_grep agents/orchestrator.md "await upstreaming" \
  "orchestrator session-start reports stray records"
expect_grep agents/orchestrator.md "Amendment 2026-07-12 — gap detection" \
  "orchestrator amendment note recorded"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
