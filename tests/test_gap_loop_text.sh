#!/usr/bin/env bash
# tests/test_gap_loop_text.sh — verifies the self-growth loop landed in the agent
# files: the orchestrator's "Growing the team" section, the growing-the-team
# skill (drafts marked provisional), and the architect + workforce-skill hooks
# into it. Presence checks, not drift checks: a future edit that drops one of
# these silently disables the loop.
# Spec: docs/superpowers/specs/2026-07-18-autonomy-first-redesign.md
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

# --- orchestrator carries the self-growth loop ---
expect_grep agents/orchestrator.md "Growing the team" \
  "orchestrator has the Growing the team section"
expect_grep agents/orchestrator.md "growing-the-team" \
  "orchestrator names the growing-the-team skill"
expect_grep agents/orchestrator.md "provenance: provisional" \
  "orchestrator marks drafts provisional"

# --- the growing-the-team skill exists and routes on 'provisional' ---
SKILL_FILE="skills/growing-the-team/SKILL.md"
if [ -f "$ROOT/$SKILL_FILE" ]; then
  PASS=$((PASS+1)); echo "PASS: growing-the-team skill exists"
else
  FAIL=$((FAIL+1)); echo "FAIL: growing-the-team skill exists — missing $SKILL_FILE"
fi

# Frontmatter description mentions 'provisional' (check the frontmatter block
# only: between the opening and closing '---').
if [ -f "$ROOT/$SKILL_FILE" ] && \
   awk '/^---$/{n++; next} n==1' "$ROOT/$SKILL_FILE" | grep '^description:' | grep -qF -- "provisional"; then
  PASS=$((PASS+1)); echo "PASS: growing-the-team frontmatter description says provisional"
else
  FAIL=$((FAIL+1)); echo "FAIL: growing-the-team frontmatter description says provisional — not found in $SKILL_FILE"
fi

# --- the rest of the team hooks into the loop ---
expect_grep agents/architect.md "growing-the-team" \
  "architect drafts skills via growing-the-team"
expect_grep skills/agent-workforce/SKILL.md "growing-the-team" \
  "workforce skill applies the growing-the-team discipline"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
