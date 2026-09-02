#!/usr/bin/env bash
# tests/lib/workspace-adopt-cases.sh — the workspace primitive on a HUMAN-NAMED worktree:
# one the human made, recorded on the timecard as adopted. `ensure` accepts it and creates
# nothing; `integrate` merges what the worktree's HEAD holds and leaves the worktree and
# its ref in place, because this library did not create them and they are the human's;
# `remove` releases the claim and leaves the tree for the same reason.
#
# Sourced by tests/test_workspace.sh after its fixture and helpers; sourcing defines the
# cases and RUNS them. Split out for the project's file-size discipline.

# A detached worktree the human made under `.worktrees/`, which the fixture ignores as the
# originating project does, holding one commit that main does not.
adopt_fixture() { # $1 name -> sets NAMED_WT and claims "human-change" on it
  fixture "$1" || return 1
  printf '.worktrees/\n' >> "$PROJ/.gitignore"
  git -C "$PROJ" add -A >/dev/null 2>&1
  git -C "$PROJ" commit -qm "chore: ignore human worktrees" >/dev/null 2>&1
  NAMED_WT="$PROJ/.worktrees/human_plan"
  git -C "$PROJ" worktree add -q --detach "$NAMED_WT" HEAD >/dev/null 2>&1 || return 1
  printf 'from the human worktree\n' > "$NAMED_WT/plan.md"
  git -C "$NAMED_WT" add -A >/dev/null 2>&1
  git -C "$NAMED_WT" commit -qm "docs: the plan" >/dev/null 2>&1 || return 1
  bash "$REG" claim "$PROJ" human-change sess-adopt "$NAMED_WT" >/dev/null 2>&1
}

case_ensure_adopts_named_tree() {
  adopt_fixture ensure-named || { printf 'fixture setup failed'; return 1; }
  local out
  out="$(ws ensure "$PROJ" human-change main "$NAMED_WT")" \
    || { printf 'expected ensure to accept the named worktree; observed %s' "$out"; return 1; }
  [ "$out" = "$NAMED_WT" ] || { printf 'expected the named path printed; observed %s' "$out"; return 1; }
  [ -d "$WTPATH/human-change" ] && { printf 'expected no derived worktree created'; return 1; }
  git -C "$PROJ" show-ref --verify --quiet refs/heads/change/human-change \
    && { printf 'expected no derived ref created'; return 1; }
  return 0
}

case_ensure_refuses_named_path_not_registered() {
  adopt_fixture ensure-unregistered || { printf 'fixture setup failed'; return 1; }
  local out rc
  mkdir -p "$PROJ/plain"
  out="$(ws ensure "$PROJ" human-change main "$PROJ/plain")"
  rc=$?
  [ "$rc" -eq 7 ] || { printf 'expected exit 7 for a path git does not list; observed exit=%s out=%s' "$rc" "$out"; return 1; }
  case "$out" in *"worktree list"*) return 0 ;; *) printf 'expected the refusal to name git worktree list; observed %s' "$out"; return 1 ;; esac
}

case_integrate_adopted_merges_and_keeps_tree() {
  adopt_fixture integrate-named || { printf 'fixture setup failed'; return 1; }
  local out cp
  cp="$(bash "$REG" card-path "$PROJ" human-change)"
  out="$(ws integrate "$PROJ" human-change main sess-adopt)" \
    || { printf 'expected integrate to succeed; observed %s' "$out"; return 1; }
  [ -f "$PROJ/plan.md" ] || { printf 'expected the worktree'"'"'s commit merged into main'; return 1; }
  [ -d "$NAMED_WT" ] || { printf 'expected the human worktree left in place'; return 1; }
  git -C "$PROJ" worktree list --porcelain | grep -q "^worktree $NAMED_WT\$" \
    || { printf 'expected the human worktree still registered'; return 1; }
  [ -f "$cp" ] && { printf 'expected the claim released'; return 1; }
  case "$out" in *"left in place"*) return 0 ;; *) printf 'expected the output to say the tree was left in place; observed %s' "$out"; return 1 ;; esac
}

case_remove_adopted_releases_claim_keeps_tree() {
  adopt_fixture remove-named || { printf 'fixture setup failed'; return 1; }
  local out cp
  cp="$(bash "$REG" card-path "$PROJ" human-change)"
  out="$(ws remove "$PROJ" human-change sess-adopt)" \
    || { printf 'expected remove to succeed on an adopted claim; observed %s' "$out"; return 1; }
  [ -f "$cp" ] && { printf 'expected the claim released'; return 1; }
  [ -d "$NAMED_WT" ] || { printf 'expected the human worktree left in place'; return 1; }
  [ -f "$NAMED_WT/plan.md" ] || { printf 'expected the human worktree'"'"'s work untouched'; return 1; }
  return 0
}

run_case 'ensure accepts a human-named worktree and creates nothing' case_ensure_adopts_named_tree
run_case 'ensure refuses a named path git does not list as a worktree' case_ensure_refuses_named_path_not_registered
run_case 'integrate merges a human-named worktree and leaves it in place' case_integrate_adopted_merges_and_keeps_tree
run_case 'remove releases the claim on a human-named worktree and leaves it in place' case_remove_adopted_releases_claim_keeps_tree
