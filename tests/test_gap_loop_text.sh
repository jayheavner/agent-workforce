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

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
