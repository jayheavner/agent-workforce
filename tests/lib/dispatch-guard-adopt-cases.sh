#!/usr/bin/env bash
# tests/lib/dispatch-guard-adopt-cases.sh — a human-named worktree. The dispatch carries a
# second line, `WORKTREE: <absolute path>`, beside its `CHANGE: <slug>` line, and the
# guard ADOPTS that worktree instead of creating one at the derived path: the path is
# recorded on the timecard, so the worktree guard confines the agent to it, and nothing
# is created. Without the line the guard creates the derived worktree as before.
#
# Why this exists: on 2026-09-01 the human named the worktree where a plan lived and
# forbade writes anywhere else; the guard refused the line by name and offered only a
# worktree it would create itself. Where work happens is the human's call.
#
# Sourced by tests/test_dispatch_guard.sh after tests/lib/dispatch-guard-fixture.sh;
# sourcing defines these cases and RUNS them.

# A worktree the human made: outside .claude/worktrees, detached or on a ref of their
# own naming. `.worktrees/` is ignored, as it is in the project this case comes from.
dg_named_worktree() { # $1 path [$2 ref-short-name] -> creates it under $PROJ
  if [ -n "${2:-}" ]; then
    git -C "$PROJ" worktree add -q "$1" -b "$2" HEAD >/dev/null 2>&1 || return 1
  else
    git -C "$PROJ" worktree add -q --detach "$1" HEAD >/dev/null 2>&1 || return 1
  fi
  printf '.worktrees/\n' >> "$PROJ/.gitignore"
  git -C "$PROJ" add -A >/dev/null 2>&1
  git -C "$PROJ" commit -qm "chore: ignore human worktrees" >/dev/null 2>&1
}

named_prompt() { # $1 slug $2 path
  printf 'Implement it.\nCHANGE: %s\nWORKTREE: %s\n%s\n' "$1" "$2" "$CRITERIA_BODY"
}

case_named_worktree_adopted() {
  dg_fixture adopt-named || { printf 'fixture setup failed'; return 1; }
  local wt="$PROJ/.worktrees/human_plan" cp
  dg_named_worktree "$wt" || { printf 'could not create the human worktree'; return 1; }
  run "$(dg_payload builder "$(named_prompt plan-work "$wt")" sess-named "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected exit 0; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  cp="$(card_path plan-work)"
  jq -e --arg wt "$wt" '.worktree == $wt and .adopted == true and .ref == "detached"
                        and .state == "ready" and .writer.slot == "builder#0"' "$cp" >/dev/null 2>&1 \
    || { printf 'expected a ready card recording the named worktree as adopted; observed %s' \
         "$(head -c 300 "$cp" 2>/dev/null)"; return 1; }
  [ -d "$PROJ/.claude/worktrees/plan-work" ] \
    && { printf 'expected no derived worktree created when one was named'; return 1; }
  return 0
}

case_named_worktree_on_a_ref_records_it() {
  dg_fixture adopt-named-ref || { printf 'fixture setup failed'; return 1; }
  local wt="$PROJ/.worktrees/on_a_ref"
  dg_named_worktree "$wt" topic/human-ref || { printf 'could not create the human worktree'; return 1; }
  run "$(dg_payload builder "$(named_prompt ref-work "$wt")" sess-named-ref "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected exit 0; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e '.ref == "refs/heads/topic/human-ref" and .adopted == true' "$(card_path ref-work)" >/dev/null 2>&1 \
    || { printf 'expected the card to record the worktree'"'"'s own ref; observed %s' \
         "$(head -c 300 "$(card_path ref-work)" 2>/dev/null)"; return 1; }
  return 0
}

# A path that is not a worktree git knows is refused before anything is claimed, and the
# refusal tells the reader how to see what git does know.
case_named_path_not_a_worktree_refused() {
  dg_fixture adopt-not-wt || { printf 'fixture setup failed'; return 1; }
  mkdir -p "$PROJ/plain-dir"
  run "$(dg_payload builder "$(named_prompt plain-work "$PROJ/plain-dir")" sess-plain "$PROJ" "")"
  [ "$RC" -eq 2 ] || { printf 'expected exit 2 for a directory that is no worktree; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  case "$OUT" in *"worktree list"*) ;; *) printf 'expected the refusal to name git worktree list; observed %s' "$OUT"; return 1 ;; esac
  [ -f "$(card_path plain-work)" ] && { printf 'expected no claim written'; return 1; }
  run "$(dg_payload builder "$(named_prompt gone-work "$PROJ/does-not-exist")" sess-plain "$PROJ" "")"
  [ "$RC" -eq 2 ] || { printf 'expected exit 2 for a path that does not exist; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  [ -f "$(card_path gone-work)" ] && { printf 'expected no claim written for the missing path'; return 1; }
  return 0
}

case_named_path_must_be_absolute() {
  dg_fixture adopt-relative || { printf 'fixture setup failed'; return 1; }
  dg_named_worktree "$PROJ/.worktrees/rel" || { printf 'could not create the human worktree'; return 1; }
  run "$(dg_payload builder "$(named_prompt rel-work ".worktrees/rel")" sess-rel "$PROJ" "")"
  [ "$RC" -eq 2 ] || { printf 'expected exit 2 for a relative path; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  case "$OUT" in *absolute*) ;; *) printf 'expected the refusal to say absolute; observed %s' "$OUT"; return 1 ;; esac
  return 0
}

# The shared checkout is not isolation, so naming it is refused.
case_named_path_is_shared_checkout_refused() {
  dg_fixture adopt-root || { printf 'fixture setup failed'; return 1; }
  run "$(dg_payload builder "$(named_prompt root-work "$PROJ")" sess-root "$PROJ" "")"
  [ "$RC" -eq 2 ] || { printf 'expected exit 2 for the shared checkout; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  [ -f "$(card_path root-work)" ] && { printf 'expected no claim written'; return 1; }
  return 0
}

# Once the card records the named worktree, a later dispatch of the same change needs no
# WORKTREE line: the card is the authority, and nothing is created at the derived path.
case_later_dispatch_follows_the_card() {
  dg_fixture adopt-follow || { printf 'fixture setup failed'; return 1; }
  local wt="$PROJ/.worktrees/follow_me"
  dg_named_worktree "$wt" || { printf 'could not create the human worktree'; return 1; }
  run "$(dg_payload builder "$(named_prompt follow-work "$wt")" sess-follow "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the first dispatch allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  run "$(dg_payload verifier "Check it.
CHANGE: follow-work
$CRITERIA_BODY" sess-follow "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the second dispatch allowed without a WORKTREE line; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  jq -e --arg wt "$wt" '.worktree == $wt' "$(card_path follow-work)" >/dev/null 2>&1 \
    || { printf 'expected the card to keep the named worktree'; return 1; }
  [ -d "$PROJ/.claude/worktrees/follow-work" ] \
    && { printf 'expected no derived worktree created by the second dispatch'; return 1; }
  return 0
}

# One change, one worktree. A later dispatch naming a DIFFERENT worktree for the same
# change is refused with both paths named, and the claim is left as it was.
case_conflicting_worktree_refused() {
  dg_fixture adopt-conflict || { printf 'fixture setup failed'; return 1; }
  local a="$PROJ/.worktrees/first" b="$PROJ/.worktrees/second"
  dg_named_worktree "$a" || { printf 'could not create the first worktree'; return 1; }
  git -C "$PROJ" worktree add -q --detach "$b" HEAD >/dev/null 2>&1 || { printf 'could not create the second worktree'; return 1; }
  run "$(dg_payload builder "$(named_prompt one-change "$a")" sess-conflict "$PROJ" "")"
  [ "$RC" -eq 0 ] || { printf 'expected the first dispatch allowed; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  run "$(dg_payload verifier "Check it.
CHANGE: one-change
WORKTREE: $b
$CRITERIA_BODY" sess-conflict "$PROJ" "")"
  [ "$RC" -eq 2 ] || { printf 'expected the conflicting worktree refused; observed exit=%s out=%s' "$RC" "$OUT"; return 1; }
  case "$OUT" in *"$a"*"$b"* | *"$b"*"$a"*) ;; *) printf 'expected both paths named; observed %s' "$OUT"; return 1 ;; esac
  jq -e --arg wt "$a" '.worktree == $wt' "$(card_path one-change)" >/dev/null 2>&1 \
    || { printf 'expected the card unchanged'; return 1; }
  return 0
}

run_case 'a dispatch naming an existing worktree adopts it and creates nothing' case_named_worktree_adopted
run_case 'a named worktree on its own ref records that ref' case_named_worktree_on_a_ref_records_it
run_case 'a named path git does not list as a worktree is refused and nothing is claimed' case_named_path_not_a_worktree_refused
run_case 'a named path must be absolute' case_named_path_must_be_absolute
run_case 'naming the shared checkout is refused' case_named_path_is_shared_checkout_refused
run_case 'a later dispatch of the change follows the card without a WORKTREE line' case_later_dispatch_follows_the_card
run_case 'a different worktree for a claimed change is refused with both paths named' case_conflicting_worktree_refused
