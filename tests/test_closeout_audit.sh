#!/usr/bin/env bash
# tests/test_closeout_audit.sh — red/green coverage for the completion closeout
# audit and its load-bearing memory/ledger contract.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
AUDIT="$ROOT/bin/agent-workforce-closeout"
TMPDIR_T="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_T"' EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

expect_grep() { # $1 file, $2 fixed text, $3 label
  grep -qF -- "$2" "$ROOT/$1" && ok || bad "$3";
}

REPO="$TMPDIR_T/repo"
LINKED="$TMPDIR_T/linked"
mkdir -p "$REPO"
# git init -b needs git >= 2.28; symbolic-ref names the unborn branch on any git.
git init -q "$REPO"
git -C "$REPO" symbolic-ref HEAD refs/heads/main
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name "Closeout Test"
printf 'base\n' > "$REPO/README"
git -C "$REPO" add README
git -C "$REPO" commit -qm "test: base commit"

git -C "$REPO" branch codex/old
git -C "$REPO" branch codex/open
git -C "$REPO" checkout -q codex/open
printf 'open\n' > "$REPO/open.txt"
git -C "$REPO" add open.txt
git -C "$REPO" commit -qm "test: open branch change"
git -C "$REPO" checkout -q main
git -C "$REPO" branch codex/merged
git -C "$REPO" worktree add -q "$LINKED" codex/merged

printf 'merged\n' > "$LINKED/merged.txt"
git -C "$LINKED" add merged.txt
git -C "$LINKED" commit -qm "test: merged branch change"
git -C "$REPO" merge --no-ff -qm "test: merge branch" codex/merged
git -C "$REPO" checkout -q main

JSON_OUT="$(bash "$AUDIT" --repo "$REPO" --base main --format json 2>/dev/null)"
if printf '%s' "$JSON_OUT" | jq empty >/dev/null 2>&1; then ok; else bad "JSON output is valid"; fi
if printf '%s' "$JSON_OUT" | jq -e '.repository | endswith("/repo")' >/dev/null; then ok; else bad "JSON reports repository"; fi
if printf '%s' "$JSON_OUT" | jq -e '.current_branch == "main" and .base_branch == "main" and .dirty == false' >/dev/null; then ok; else bad "JSON reports clean main state"; fi
if printf '%s' "$JSON_OUT" | jq -e '.branches[] | select(.name == "codex/old" and .merged_into_base == true and .cleanup_candidate == true)' >/dev/null; then ok; else bad "merged unshared branch is a cleanup candidate"; fi
if printf '%s' "$JSON_OUT" | jq -e '.branches[] | select(.name == "codex/open" and .merged_into_base == false and .cleanup_candidate == false)' >/dev/null; then ok; else bad "open branch is not a cleanup candidate"; fi
if printf '%s' "$JSON_OUT" | jq -e '.worktrees[] | select((.path | endswith("/linked")) and .branch == "codex/merged" and .clean == true and .cleanup_candidate == true)' >/dev/null; then ok; else bad "clean merged linked worktree is a cleanup candidate"; fi
if printf '%s' "$JSON_OUT" | jq -e '.cleanup_candidates.branches | index("codex/old") != null' >/dev/null; then ok; else bad "branch candidate is listed"; fi
if printf '%s' "$JSON_OUT" | jq -e '.cleanup_candidates.worktrees | any(endswith("/linked"))' >/dev/null; then ok; else bad "worktree candidate is listed"; fi

TEXT_OUT="$(bash "$AUDIT" --repo "$REPO" --base main --format text 2>/dev/null)"
printf '%s' "$TEXT_OUT" | grep -qF 'CLOSEOUT AUDIT' && ok || bad "text output has closeout heading"
printf '%s' "$TEXT_OUT" | grep -qF 'cleanup candidates' && ok || bad "text output has cleanup section"

set +e
bash "$AUDIT" --repo "$TMPDIR_T/not-a-repo" >/dev/null 2>&1
RC=$?
set -u
[ "$RC" -eq 2 ] && ok || bad "non-repository exits 2"

expect_grep docs/memory/README.md "project records rather than personal Codex memory" \
  "memory format distinguishes project memory from personal memory"
expect_grep docs/memory/README.md "Secret handling" \
  "memory format has a secret-handling section"
for field in verification review documentation memory commit deployment integration cleanup; do
  expect_grep skills/finishing-a-branch/SKILL.md "$field" \
    "finishing skill names closeout field: $field"
done
expect_grep skills/agent-workforce/SKILL.md "closeout ledger" \
  "workforce skill requires a closeout ledger"
expect_grep agents/orchestrator.md "memory: not requested" \
  "orchestrator defines explicit memory state"

printf 'closeout-audit tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
