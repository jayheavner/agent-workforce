#!/usr/bin/env bash
# tests/test_worktree_hygiene.sh — verifies tools/worktree-hygiene.sh reports
# removal candidates without ever mutating the repository.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SCRIPT="$ROOT/tools/worktree-hygiene.sh"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }

FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/worktree-hygiene-fixture.XXXXXX")"
REPO="$FIXTURE_ROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email "test@example.invalid"
git -C "$REPO" config user.name "Hygiene Test"
echo base > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -qm "test: baseline"

# Worktree A: merged into main, clean tree -> removal candidate.
git -C "$REPO" branch merged-clean
git -C "$REPO" worktree add -q "$FIXTURE_ROOT/merged-clean" merged-clean
WT_A="$(cd "$FIXTURE_ROOT/merged-clean" && pwd -P)"

# Worktree B: has a unique commit not on main -> keep (unique commits).
git -C "$REPO" branch diverged
git -C "$REPO" worktree add -q "$FIXTURE_ROOT/diverged" diverged
WT_B="$(cd "$FIXTURE_ROOT/diverged" && pwd -P)"
echo unique > "$WT_B/unique.md"
git -C "$WT_B" add unique.md
git -C "$WT_B" commit -qm "feat: unique work"

OUTPUT="$(bash "$SCRIPT" "$REPO" 2>&1)"
RC=$?

if [ "$RC" -eq 0 ]; then ok; else bad "script exits 0 always (rc=$RC)"; fi

if printf '%s' "$OUTPUT" | grep -qF -e "$WT_A"; then
  ok
else
  bad "output lists worktree A ($WT_A)"
fi

if printf '%s' "$OUTPUT" | grep -F -e "$WT_A" | grep -qF -e "candidate"; then
  ok
else
  bad "worktree A (merged, clean) is listed as a candidate"
fi

if printf '%s' "$OUTPUT" | grep -F -e "$WT_A" | grep -qF -e "git worktree remove $WT_A"; then
  ok
else
  bad "worktree A shows its exact removal command"
fi

if printf '%s' "$OUTPUT" | grep -F -e "$WT_B" | grep -qF -e "keep: unique commits"; then
  ok
else
  bad "worktree B (diverged) is listed as keep: unique commits"
fi

if printf '%s' "$OUTPUT" | grep -qF -e "1 removal candidate"; then
  ok
else
  bad "summary line reads '1 removal candidate(s)' (output: $OUTPUT)"
fi

# Read-only: repo state must be byte-identical before and after the run.
BEFORE_REFS="$(git -C "$REPO" for-each-ref)"
BEFORE_WORKTREES="$(git -C "$REPO" worktree list --porcelain)"
bash "$SCRIPT" "$REPO" >/dev/null 2>&1
AFTER_REFS="$(git -C "$REPO" for-each-ref)"
AFTER_WORKTREES="$(git -C "$REPO" worktree list --porcelain)"
if [ "$BEFORE_REFS" = "$AFTER_REFS" ] && [ "$BEFORE_WORKTREES" = "$AFTER_WORKTREES" ]; then
  ok
else
  bad "script mutated repo refs or worktrees (must be read-only)"
fi

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck "$SCRIPT" >/dev/null 2>&1; then
    ok
  else
    bad "shellcheck reported issues in $SCRIPT"
  fi
else
  echo "worktree-hygiene tests: shellcheck not present in this environment — skipped"
fi

rm -rf "$FIXTURE_ROOT"

printf 'worktree-hygiene tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
