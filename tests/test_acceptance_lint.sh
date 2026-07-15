#!/usr/bin/env bash
# tests/test_acceptance_lint.sh — executable form of the acceptance-check-linting
# spec §5 (docs/superpowers/specs/2026-07-13-acceptance-check-linting-design.md).
# Truth table over tests/fixtures/acceptance-lint/:
#   tautology.md  -> BLOCK tautological-check (AC-1 echo chain, AC-2 bare true), exit 1
#   silent.md     -> BLOCK silent-check x3 (grep -q / diff -q / bare test -f), exit 1
#   guarded.md    -> the SAME three checks with `|| echo "why…"` -> zero findings, exit 0
#                    (false-positive guard: the dangerous direction for a blocking lint)
#   nocheck.md    -> BLOCK mechanical-criterion-without-check, exit 1
#   nobar.md      -> WARN empty-judgment-criterion, exit 0 (advisory never blocks)
#   weasel.md     -> WARN unfalsifiable-phrasing ("gracefully"), exit 0
#   mislabeled.md -> WARN mislabeled-criterion (judgment claim with observable token), exit 0
#   clean.md      -> zero findings, exit 0
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
TOOL="$REPO/tools/lint_acceptance_checks.py"
FIX="$HERE/fixtures/acceptance-lint"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL [$1]"; }

lint() { # $1 fixture -> sets OUT and RC
  set +e
  OUT="$(python3 "$TOOL" "$FIX/$1" 2>&1)"; RC=$?
  set -u
}

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not available (tool degrades to reviewer-eyes-only)"; exit 0; }

lint tautology.md
[ "$RC" -ne 0 ] && ok || no "tautology.md exits non-zero"
printf '%s\n' "$OUT" | grep -q "BLOCK tautological-check AC-1" && ok || no "echo-chain check is BLOCK tautological-check"
printf '%s\n' "$OUT" | grep -q "BLOCK tautological-check AC-2" && ok || no "bare true is BLOCK tautological-check"
printf '%s\n' "$OUT" | grep -q "good:" && ok || no "finding carries a what-good-looks-like nudge"

lint silent.md
[ "$RC" -ne 0 ] && ok || no "silent.md exits non-zero"
printf '%s\n' "$OUT" | grep -q "BLOCK silent-check AC-1" && ok || no "grep -q is BLOCK silent-check"
printf '%s\n' "$OUT" | grep -q "BLOCK silent-check AC-2" && ok || no "diff -q is BLOCK silent-check"
printf '%s\n' "$OUT" | grep -q "BLOCK silent-check AC-3" && ok || no "bare test -f is BLOCK silent-check"

lint guarded.md
[ "$RC" -eq 0 ] && ok || no "guarded.md exits 0 (|| echo branch defuses silent-check)"
[ -z "$(printf '%s\n' "$OUT" | grep -E '^(BLOCK|WARN)')" ] && ok || no "guarded checks produce zero findings (got: $OUT)"

lint nocheck.md
[ "$RC" -ne 0 ] && ok || no "nocheck.md exits non-zero"
printf '%s\n' "$OUT" | grep -q "BLOCK mechanical-criterion-without-check AC-1" && ok || no "mechanical without Check: is BLOCK"

lint nobar.md
[ "$RC" -eq 0 ] && ok || no "nobar.md exits 0 (advisory never blocks)"
printf '%s\n' "$OUT" | grep -q "WARN empty-judgment-criterion AC-1" && ok || no "judgment without Bar: is WARN empty-judgment-criterion"

lint weasel.md
[ "$RC" -eq 0 ] && ok || no "weasel.md exits 0"
printf '%s\n' "$OUT" | grep -q "WARN unfalsifiable-phrasing AC-1" && ok || no "weasel phrasing is WARN unfalsifiable-phrasing"

lint mislabeled.md
[ "$RC" -eq 0 ] && ok || no "mislabeled.md exits 0"
printf '%s\n' "$OUT" | grep -q "WARN mislabeled-criterion AC-1" && ok || no "observable-token judgment claim is WARN mislabeled-criterion"

lint clean.md
[ "$RC" -eq 0 ] && ok || no "clean.md exits 0"
[ -z "$(printf '%s\n' "$OUT" | grep -E '^(BLOCK|WARN)')" ] && ok || no "clean plan produces zero findings (got: $OUT)"

# A plan with no tagged criteria (legacy shape) is not retroactively failed.
lint ../../../README.md
[ "$RC" -eq 0 ] && ok || no "untagged legacy document exits 0"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
