#!/usr/bin/env bash
# tests/test_decision_discipline_drift.sh — the canonical two-questions block
# must be identical (modulo trailing whitespace) across the three agent files.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
AGENTS="$HERE/../agents"
FILES="architect.md reviewer.md orchestrator.md"
PASS=0
FAIL=0

# Extract the marker-delimited block, stripping trailing whitespace per line.
extract() {
  awk '/<!-- two-questions:start -->/{f=1;next} /<!-- two-questions:end -->/{f=0} f' "$1" \
    | sed 's/[[:space:]]*$//'
}

REF=""
REF_FILE=""
for f in $FILES; do
  path="$AGENTS/$f"
  block="$(extract "$path")"
  if [ -z "$block" ]; then
    FAIL=$((FAIL+1)); echo "FAIL: $f has no non-empty two-questions block"; continue
  fi
  if [ -z "$REF" ]; then
    REF="$block"; REF_FILE="$f"; PASS=$((PASS+1)); continue
  fi
  if [ "$block" = "$REF" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL: $f block differs from $REF_FILE"
    diff <(printf '%s' "$REF") <(printf '%s' "$block") || true
  fi
done

echo "decision-discipline drift tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
