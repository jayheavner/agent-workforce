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

# --- reads are never restricted: every role must read its inputs.
allow scribe "$(read_payload "$REPO/src/app.py")" "scribe reading source allows"
allow test-author "$(read_payload "$REPO/src/app.py")" "test-author reading source allows"

# --- traversal cannot escape the lane.
block scribe "$(write_payload "$REPO/docs/../src/app.py")" "traversal out of the scribe lane blocks"

# --- writes outside the repository entirely are outside every lane.
block scribe "$(write_payload "$WORK/loose.md")" "scribe writing outside the repo blocks"

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

echo "lane-guard tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
