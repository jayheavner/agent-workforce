#!/usr/bin/env bash
# tests/lib/worktree-guard-resolution-cases.sh — WHICH CHANGE governs the agent that
# is acting, and which writes that change makes legal.
#
# Sourced by tests/test_worktree_guard.sh, whose fixture (MAIN, WT_MINE, WT_OTHER,
# the `card`, `own_tr`, `session_tr` and payload helpers, and the pass/fail
# reporters) these cases reuse; sourcing defines the helpers below and RUNS the
# cases, so the whole suite is still one command. Split out only for the project's
# file-size discipline.
#
# Every group here gets its OWN register directory, because "how many live claims
# does this session hold" is the question under test and a shared register would
# answer it once for every case.

# An empty register of its own, pointed at by the environment the guard reads.
res_register() { # $1 name -> sets RES_REG and exports AGENT_TEAM_REGISTER_DIR
  RES_REG="$WORK/reg-$1"
  mkdir -p "$RES_REG"
  chmod 700 "$RES_REG"
  export AGENT_TEAM_REGISTER_DIR="$RES_REG"
}

# --- ONE candidate needs no selector ----------------------------------------
res_register one-claim
card solo "$WT_MINE" "$SESSION" "$RES_REG" || fail "fixture" "could not write the solo timecard"
TR_NO_SELECTOR="$(own_tr "Do the work. This dispatch names no change.")"
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_NO_SELECTOR")" \
  "one live claim resolves with no selector"
block builder "$(write_payload "$MAIN/file.txt" "$TR_NO_SELECTOR")" \
  "one live claim still confines the write"

# A main session's transcript accumulates every dispatch it ever made. Two
# declarations in it used to mean "the guard picks by recency" — the 2026-08-04
# defect. It now means "no selector at all", and the register decides alone.
TR_MAIN_SESSION="$(session_tr "Implement it.
CHANGE: poisoned-by-an-older-dispatch" "Implement it.
CHANGE: some-later-dispatch")"
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_MAIN_SESSION")" \
  "a main session's declarations are no selector, so the register alone resolves"

# --- a HUMAN-NAMED worktree confines exactly like a derived one ---------------
# The card records where the change works; the guard reads that, never the derived
# path. A worktree the human made under `.worktrees/`, detached, is the 2026-09-01 case.
res_register named-claim
WT_NAMED="$MAIN/.worktrees/human_plan"
git -C "$MAIN" worktree add -q --detach "$WT_NAMED" HEAD
card named "$WT_NAMED" "$SESSION" "$RES_REG" || fail "fixture" "could not write the named timecard"
TR_NAMED="$(own_tr "Do the work.
CHANGE: named")"
allow builder "$(write_payload "$WT_NAMED/new.py" "$TR_NAMED")" \
  "a claim on a human-named worktree allows writes inside it"
block builder "$(write_payload "$MAIN/file.txt" "$TR_NAMED")" \
  "a claim on a human-named worktree still confines writes to it"
block builder "$(write_payload "$WT_MINE/new.py" "$TR_NAMED")" \
  "a claim on a human-named worktree refuses the derived path of another change"

# --- MORE THAN ONE candidate, and nothing to choose between them -------------
res_register two-claims
card alpha "$WT_MINE" "$SESSION" "$RES_REG" || fail "fixture" "could not write the alpha timecard"
card beta "$WT_OTHER" "$SESSION" "$RES_REG" || fail "fixture" "could not write the beta timecard"
TR_AMBIGUOUS="$(own_tr "Do the work. This dispatch names no change.")"
TR_SELECT_ALPHA="$(own_tr "Do the work.
CHANGE: alpha")"
TR_SELECT_BETA="$(own_tr "Do the work.
CHANGE: beta")"
TR_SELECT_GAMMA="$(own_tr "Do the work.
CHANGE: gamma")"

block_naming builder "$(write_payload "$WT_MINE/new.py" "$TR_AMBIGUOUS")" \
  "two live claims with no selector is a refusal naming both" \
  alpha beta "CHANGE:"
block_naming builder "$(write_payload "$WT_MINE/new.py" "$TR_SELECT_GAMMA")" \
  "a selector naming no live claim is a refusal naming both" \
  alpha beta gamma
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_SELECT_ALPHA")" \
  "a subagent's own dispatch prompt selects among its session's claims"
block builder "$(write_payload "$WT_MINE/new.py" "$TR_SELECT_BETA")" \
  "the selector confines to the change it names, not to the other candidate"
allow builder "$(write_payload "$WT_OTHER/new.py" "$TR_SELECT_BETA")" \
  "and the other candidate is legal once its own dispatch selects it"
# The selector is read from the agent's OWN transcript only. The same two claims
# with a main session's file supply no selector, so the ambiguity stands.
TR_MAIN_TWO="$(session_tr "Implement it.
CHANGE: alpha")"
block_naming builder "$(write_payload "$WT_MINE/new.py" "$TR_MAIN_TWO")" \
  "a declaration in a main session's transcript cannot resolve the ambiguity" \
  alpha beta

# --- a claim another session holds is not this session's candidate -----------
res_register foreign-claim
card elsewhere "$WT_MINE" sess-somebody-else "$RES_REG" || fail "fixture" "could not write the foreign timecard"
TR_FOREIGN="$(own_tr "Do the work.
CHANGE: elsewhere")"
block_naming builder "$(write_payload "$WT_MINE/new.py" "$TR_FOREIGN")" \
  "a claim held by another session is not this session's candidate" \
  "CHANGE:"

# --- decision 7's second branch: a lane outside every git working tree -------
# The scribe's agent memory is in no worktree and never can be, so a rule of
# "inside the claimed tree or nowhere" outlawed a write the workflow depends on.
res_register lanes
LANE_HOME="$WORK/lane-home"
mkdir -p "$LANE_HOME/.claude/projects/-fixture/memory"
TR_NO_CLAIM="$(own_tr "Record the lesson. No change is declared.")"
GOUT="$(printf '%s' "$(write_payload "$LANE_HOME/.claude/projects/-fixture/memory/lesson.md" "$TR_NO_CLAIM" "$MAIN")" \
  | HOME="$LANE_HOME" bash "$GUARD" scribe 2>&1)"
if [ "$?" -eq 0 ]; then
  pass "the scribe's agent-memory lane is legal with no claim at all"
else
  fail "the scribe's agent-memory lane is legal with no claim at all" "$(brief "$GOUT")"
fi
# The same role's IN-REPOSITORY lane is not: a document that belongs to a change
# lives inside that change, and the refusal names the one line that repairs it.
block_naming scribe "$(write_payload "$MAIN/docs/note.md" "$TR_NO_CLAIM" "$MAIN")" \
  "an in-repository lane with no claim is refused and names the CHANGE: repair" \
  "CHANGE:"
block_naming builder "$(write_payload "$LANE_HOME/.claude/projects/-fixture/memory/lesson.md" "$TR_NO_CLAIM" "$MAIN")" \
  "a lane another role owns is not this role's escape" \
  "CHANGE:"

# The plan document lives with the change it plans.
res_register architect-plan
card plan-change "$WT_MINE" "$SESSION" "$RES_REG" || fail "fixture" "could not write the plan timecard"
TR_PLAN="$(own_tr "Write the plan.
CHANGE: plan-change")"
allow architect "$(write_payload "$WT_MINE/plans/2026-08-17-plan.md" "$TR_PLAN" "$MAIN")" \
  "an architect plan write inside the claimed tree allows"
block_naming architect "$(write_payload "$MAIN/plans/2026-08-17-plan.md" "$TR_PLAN" "$MAIN")" \
  "the same plan write in the shared checkout is refused" \
  "CHANGE:"

# --- PARALLEL_SAFE is verified, not trusted ---------------------------------
# The literal asserts the dispatch writes NOTHING. The identical write is legal
# without it and refused with it, so the assertion has teeth.
res_register parallel-safe
card solo-write "$WT_MINE" "$SESSION" "$RES_REG" || fail "fixture" "could not write the solo-write timecard"
TR_PLAIN="$(own_tr "Do the work.
CHANGE: solo-write")"
TR_SAFE="$(own_tr "Do the work.
CHANGE: solo-write
PARALLEL_SAFE: this dispatch writes nothing")"
allow builder "$(write_payload "$WT_MINE/new.py" "$TR_PLAIN")" \
  "the control write without the marker allows"
block_naming builder "$(write_payload "$WT_MINE/new.py" "$TR_SAFE")" \
  "a dispatch declaring PARALLEL_SAFE may not write" \
  PARALLEL_SAFE
# An assertion that cannot be checked is recorded as unchecked rather than trusted
# or refused: a main-session transcript carries no PARALLEL_SAFE line of this
# agent's own, and the write is judged by the timecard rule alone.
TR_SAFE_MAIN="$(session_tr "Do the work.
CHANGE: solo-write
PARALLEL_SAFE: this dispatch writes nothing")"
UNVERIFIABLE_LOG="$AGENT_TEAM_TELEMETRY_DIR/guard-blocks.jsonl"
rm -f "$UNVERIFIABLE_LOG"
run_guard builder "$(write_payload "$WT_MINE/new.py" "$TR_SAFE_MAIN")"
if [ "$GRC" -eq 0 ] && [ -f "$UNVERIFIABLE_LOG" ] \
  && grep -q 'parallel-safe-unverifiable' "$UNVERIFIABLE_LOG"; then
  pass "an uncheckable PARALLEL_SAFE assertion is recorded, not trusted silently"
else
  fail "an uncheckable PARALLEL_SAFE assertion is recorded, not trusted silently" \
    "exit=$GRC log=$(brief "$(cat "$UNVERIFIABLE_LOG" 2>/dev/null)")"
fi

# --- all ten policed roles ---------------------------------------------------
# Every role that holds Write, Edit, NotebookEdit or Bash is refused a write to the
# shared checkout, and allowed the same write inside the change's claimed worktree —
# so the refusal is confinement rather than a guard that refuses everyone
# everything. The researcher and the ticketer are absent by design: their
# frontmatter denies those tools, so there is nothing here to police.
res_register ten-roles
card roles-change "$WT_MINE" "$SESSION" "$RES_REG" || fail "fixture" "could not write the roles timecard"
TR_ROLES="$(own_tr "Do the work.
CHANGE: roles-change")"
for role in builder test-author architect scribe executor deployer verifier reviewer debugger ops; do
  block "$role" "$(write_payload "$MAIN/docs/note.md" "$TR_ROLES" "$MAIN")" \
    "shared-checkout write refused: $role"
  allow "$role" "$(write_payload "$WT_MINE/src/new.txt" "$TR_ROLES" "$MAIN")" \
    "claimed-worktree write allowed: $role"
done

export AGENT_TEAM_REGISTER_DIR="$REGDIR"
