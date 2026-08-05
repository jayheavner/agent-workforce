#!/usr/bin/env bash
# tests/test_lane_guard.sh — every file-writing role stays in the paths its role
# is for. These boundaries were prose in each agent's instructions until
# 2026-08-03; the incident that produced this guard started with a correct prose
# refusal being re-routed to a role that had no boundary at all.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/../hooks/agent-team-lane-guard.sh"
PASS=0
FAIL=0

expect() { # $1 expected_rc $2 role $3 json $4 label
  set +e
  printf '%s' "$3" | bash "$GUARD" "$2" >/dev/null 2>&1
  local rc=$?
  set -u
  if [ "$rc" -eq "$1" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL [$4]: expected=$1 got=$rc"
  fi
}
allow() { expect 0 "$1" "$2" "$3"; }
block() { expect 2 "$1" "$2" "$3"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/lane-guard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name Test
printf 'x\n' > "$REPO/seed.txt"
git -C "$REPO" add seed.txt
git -C "$REPO" commit -qm init

write_payload() { # $1 file_path
  jq -cn --arg f "$1" --arg cwd "$REPO" \
    '{hook_event_name:"PreToolUse",tool_name:"Write",cwd:$cwd,tool_input:{file_path:$f,content:"x"}}'
}
edit_payload() { # $1 file_path
  jq -cn --arg f "$1" --arg cwd "$REPO" \
    '{hook_event_name:"PreToolUse",tool_name:"Edit",cwd:$cwd,tool_input:{file_path:$f,old_string:"x",new_string:"y"}}'
}
read_payload() { # $1 file_path
  jq -cn --arg f "$1" --arg cwd "$REPO" \
    '{hook_event_name:"PreToolUse",tool_name:"Read",cwd:$cwd,tool_input:{file_path:$f}}'
}

# --- the scribe writes documents, and nothing else.
allow scribe "$(write_payload "$REPO/docs/STATUS-task.md")" "scribe writes a status note"
allow scribe "$(write_payload "$REPO/plans/design.md")" "scribe writes into plans"
allow scribe "$(write_payload "$REPO/doc-inventory/map.tsv")" "scribe writes doc-inventory"
block scribe "$(write_payload "$REPO/src/app.py")" "scribe writing source blocks"
block scribe "$(edit_payload "$REPO/tests/test_app.py")" "scribe editing a test blocks"
block scribe "$(write_payload "$REPO/hooks/guard.sh")" "scribe writing a hook blocks"

# THE INCIDENT'S FIRST MOVE: the scribe was dispatched source-and-test work and
# refused it in prose. The refusal is now mechanical.
block scribe "$(write_payload "$REPO/src/screening/prompts/guidance.json")" \
  "scribe refusing out-of-lane source is enforced, not chosen"

# --- the architect drafts plans, docs, skills, and agents.
allow architect "$(write_payload "$REPO/plans/spec.md")" "architect writes a plan"
allow architect "$(write_payload "$REPO/skills/new-skill/SKILL.md")" "architect drafts a skill"
allow architect "$(write_payload "$REPO/agents/new-role.md")" "architect drafts an agent"
block architect "$(write_payload "$REPO/src/app.py")" "architect writing source blocks"
block architect "$(write_payload "$REPO/tests/unit/test_x.py")" "architect writing a test blocks"

# --- the test-author writes tests, and never the implementation it judges.
allow test-author "$(write_payload "$REPO/tests/acceptance/test_ac.py")" "test-author writes the acceptance suite"
allow test-author "$(write_payload "$REPO/tests/unit/test_x.py")" "test-author writes a unit test"
block test-author "$(write_payload "$REPO/src/app.py")" "test-author writing source blocks"
block test-author "$(write_payload "$REPO/docs/README.md")" "test-author writing docs blocks"

# --- A LANE IS MEASURED FROM THE TREE BEING WRITTEN, NOT FROM THE SESSION'S
# DIRECTORY. Every role above writes with cwd = the parent checkout, because a
# subagent's directory is its session's and is fixed for the session's life. When
# the work happens in a linked worktree the write is absolute and lands there,
# while the directory still says parent checkout — and a root derived from the
# directory measured <worktree>/docs/x.md as ".claude/worktrees/..." from the
# parent root, which is inside no lane at all. That refused the architect its own
# plan on 2026-08-04 and cost a session five blocked attempts.
WT_LANE="$REPO/.claude/worktrees/task-a"
# Worktrees live under .claude/ and are ignored there, exactly as in this
# repository — so the fixture's own isolation cannot register as repository dirt
# in the telemetry-hygiene check below.
printf '.claude/\n' >> "$REPO/.git/info/exclude"
git -C "$REPO" worktree add -q --detach "$WT_LANE" HEAD
allow architect "$(write_payload "$WT_LANE/docs/product/plan.md")" \
  "architect writes docs inside a linked worktree"
allow architect "$(write_payload "$WT_LANE/plans/spec.md")" \
  "architect writes plans inside a linked worktree"
allow scribe "$(write_payload "$WT_LANE/docs/STATUS-task.md")" \
  "scribe writes a status note inside a linked worktree"
allow test-author "$(write_payload "$WT_LANE/tests/unit/test_x.py")" \
  "test-author writes a test inside a linked worktree"
# Rooting on the target must not widen anything: the lane still binds inside the
# worktree, so source there is refused exactly as it is in the parent checkout.
block test-author "$(write_payload "$WT_LANE/src/app.py")" \
  "test-author writing source inside a worktree still blocks"
block scribe "$(write_payload "$WT_LANE/src/app.py")" \
  "scribe writing source inside a worktree still blocks"
# The worktree's own directory is not a lane: .claude/ is neither docs nor plans.
block scribe "$(write_payload "$REPO/.claude/worktrees/task-a-note.md")" \
  "a path under .claude in the parent checkout is in no lane"

# --- reads are never restricted: every role must read its inputs.
allow scribe "$(read_payload "$REPO/src/app.py")" "scribe reading source allows"
allow test-author "$(read_payload "$REPO/src/app.py")" "test-author reading source allows"

# --- traversal cannot escape the lane.
block scribe "$(write_payload "$REPO/docs/../src/app.py")" "traversal out of the scribe lane blocks"

# --- writes outside the repository entirely are outside every lane.
block scribe "$(write_payload "$WORK/loose.md")" "scribe writing outside the repo blocks"

# --- A LANE MAY NAME AN ABSOLUTE PATH, AND THE AGENT MEMORY IS ONE.
# 2026-08-04: the agent memory at ~/.claude/projects/<project>/memory is outside
# every checkout, so no repo-relative lane could ever cover it. The scribe was
# refused it, the dispatch guard's "unclaimed means source, so the builder's"
# fallback sent it to the one role confined to a git worktree, and the worktree
# guard refused it there. Three correct guards and no role left that could write
# the file. These cases are the lane that removes the loop — and the ones that
# keep it from becoming "the scribe may write anywhere under ~/.claude", which
# would include the session transcripts every guard reads.
FAKEHOME="$WORK/home"
PROJECT_MEM="$FAKEHOME/.claude/projects/-Users-someone-project/memory"
mkdir -p "$PROJECT_MEM"
expect_home() { # $1 expected_rc $2 role $3 json $4 label
  set +e
  printf '%s' "$3" | HOME="$FAKEHOME" bash "$GUARD" "$2" >/dev/null 2>&1
  local rc=$?
  set -u
  if [ "$rc" -eq "$1" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL [$4]: expected=$1 got=$rc"
  fi
}
allow_home() { expect_home 0 "$1" "$2" "$3"; }
block_home() { expect_home 2 "$1" "$2" "$3"; }

allow_home scribe "$(write_payload "$PROJECT_MEM/feedback-never-bury-open-items.md")" \
  "scribe writes a lesson into the agent memory"
allow_home scribe "$(edit_payload "$PROJECT_MEM/MEMORY.md")" \
  "scribe edits the memory index"
allow_home scribe "$(write_payload "$FAKEHOME/.claude/projects/-not-created-yet/memory/first.md")" \
  "the memory directory need not exist yet"
# The wildcard is exactly one segment. The project directory itself holds the
# session transcripts these guards read to decide anything, and a lane that
# reached them would let an agent edit the evidence it is judged on.
block_home scribe "$(write_payload "$FAKEHOME/.claude/projects/-Users-someone-project/session.jsonl")" \
  "the project directory itself is not in the memory lane"
block_home scribe "$(write_payload "$FAKEHOME/.claude/projects/-Users-someone-project/subagents/agent-x.jsonl")" \
  "a subagent transcript is not in the memory lane"
block_home scribe "$(write_payload "$FAKEHOME/.claude/projects/-p/deeper/memory/x.md")" \
  "a wildcard matches one segment, not a run of them"
block_home scribe "$(write_payload "$FAKEHOME/.claude/settings.json")" \
  "the rest of ~/.claude is in no lane"
block_home scribe "$(write_payload "$PROJECT_MEM/../../../../.zshrc")" \
  "traversal out of the memory lane blocks"
# The memory is the scribe's, the way documents are: no other role inherits it.
block_home architect "$(write_payload "$PROJECT_MEM/lesson.md")" \
  "the architect has no memory lane"
block_home test-author "$(write_payload "$PROJECT_MEM/lesson.md")" \
  "the test-author has no memory lane"

# --- roles this guard does not police pass through untouched (the builder has
# its own worktree guard; the executor carries no file-authoring tools at all).
allow builder "$(write_payload "$REPO/src/app.py")" "builder is not policed by this guard"
allow executor "$(write_payload "$REPO/src/app.py")" "executor is not policed by this guard"
allow verifier "$(write_payload "$REPO/src/app.py")" "verifier is not policed by this guard"

# --- a project may declare its own lanes; the declaration wins over the default.
mkdir -p "$REPO/.workforce"
jq -cn '{role_lanes:{scribe:["documentation"]}}' > "$REPO/.workforce/project.json"
allow scribe "$(write_payload "$REPO/documentation/note.md")" "project-declared scribe lane allows"
block scribe "$(write_payload "$REPO/docs/note.md")" "project declaration replaces the default lane"
rm -f "$REPO/.workforce/project.json"

# --- fail closed: unusable input is a block for a policed role.
block scribe "not json" "malformed stdin blocks a policed role"
block scribe "" "empty stdin blocks a policed role"
allow builder "not json" "malformed stdin passes through for an unpoliced role"

# --- every block is recorded where it can be counted. A refusal that only
# reaches the agent's stderr is invisible, and "the scribe was refused a source
# write four times this week" is the leading indicator that routing is probing
# for a way around a control.
export AGENT_TEAM_TELEMETRY_DIR="$WORK/telemetry"
printf '%s' "$(write_payload "$REPO/src/app.py")" | bash "$GUARD" scribe >/dev/null 2>&1
LOG="$AGENT_TEAM_TELEMETRY_DIR/guard-blocks.jsonl"
if [ -f "$LOG" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [block is recorded to telemetry]"; fi
if [ -f "$LOG" ] && [ "$(jq -r '.guard' "$LOG" | head -n1)" = "lane" ]; then
  PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [telemetry line names the guard]"; fi
if [ -f "$LOG" ] && [ "$(jq -r '.role' "$LOG" | head -n1)" = "scribe" ]; then
  PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [telemetry line names the role]"; fi
if [ -f "$LOG" ] && [ "$(jq -r '.detail' "$LOG" | head -n1)" = "src/app.py" ]; then
  PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [telemetry line names the refused path]"; fi
# Telemetry must never create dirt in the repository the work is happening in.
if [ -z "$(git -C "$REPO" status --porcelain)" ]; then
  PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [telemetry wrote into the client repo]"; fi
# An unwritable telemetry dir must not change the verdict — a guard decision is
# never allowed to depend on logging succeeding.
export AGENT_TEAM_TELEMETRY_DIR="/dev/null/nope"
block scribe "$(write_payload "$REPO/src/app.py")" "block still blocks when telemetry cannot be written"
allow scribe "$(write_payload "$REPO/docs/ok.md")" "allow still allows when telemetry cannot be written"
unset AGENT_TEAM_TELEMETRY_DIR

echo "lane-guard tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
