#!/usr/bin/env bash
# tests/lib/dispatch-guard-lane-cases.sh — the dispatch guard's lane-routing cases:
# a typed refusal cannot be re-routed to the wrong role, a wrong refusal is escapable
# only by the human, and a path no lane covers is not automatically the builder's.
#
# Sourced by tests/test_dispatch_guard.sh after tests/lib/dispatch-guard-fixture.sh;
# sourcing RUNS these cases and reports each one, so the whole suite is still one
# command. Split out only for the project's file-size discipline.

# The project these cases resolve lanes and claims against.
dg_fixture lanes || { printf 'FAIL [lane fixture]: the lane fixture project could not be built\n'
  FAILED=$((FAILED + 1)); return 0 2>/dev/null || exit 1; }
LANE_PROJ="$PROJ"
LANE_SESSION="sess-lanes"
NOTHING_WRITTEN="PARALLEL_SAFE: this dispatch writes nothing"

# --- a typed lane refusal cannot be re-routed to the wrong role.
# THE INCIDENT'S FIRST MOVE (2026-08-03): the scribe refused source-and-test work as
# out of its lane, and the refusal was read as "find a wider tool". The refusal is now
# a marker this guard consumes.
write_refusal_transcript() { # $1 refused path -> prints transcript path
  local path
  path="$(mktemp "$WORK/refusal.XXXXXX")"
  jq -nc --arg role scribe \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_ref_1",name:"Agent",input:{subagent_type:$role}}]}}' \
    >"$path"
  jq -nc --arg t "Cannot do this: it is source and a test, not a document.
WORKFORCE_REFUSAL: out-of-lane | $1
WORKFORCE_REPORT: scribe | blocked" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_ref_1",content:[{type:"text",text:$t}]}]}}' \
    >>"$path"
  printf '%s' "$path"
}

append_human_turn() { # $1 transcript $2 text
  jq -nc --arg t "$2" '{type:"user",message:{role:"user",content:$t}}' >> "$1"
}
append_assistant_turn() { # $1 transcript $2 text
  jq -nc --arg t "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$1"
}
append_tool_result_turn() { # $1 transcript $2 text
  jq -nc --arg t "$2" \
    '{type:"user",toolUseResult:{stdout:""},message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_ref_9",content:[{type:"text",text:$t}]}]}}' \
    >> "$1"
}

# A builder dispatch as it now arrives: its change declared, its session named, and
# the project it is scoped to. One slug for every builder case here — the same session
# re-claiming its own change is idempotent, which is the point of the register.
lane_builder() { # $1 transcript $2 body
  dg_payload builder "CHANGE: lane-work
$CRITERIA_BODY
$2" "$LANE_SESSION" "$LANE_PROJ" "$1"
}

REFUSAL_TR="$(write_refusal_transcript "src/screening/prompts/guidance.json")"
expect_block \
  "$(agent_json_with_transcript executor "$REFUSAL_TR" "$NOTHING_WRITTEN
Apply the fix to src/screening/prompts/guidance.json and land it")" \
  "refused source path re-routed to the executor blocks"
expect_block \
  "$(agent_json_with_transcript test-author "$REFUSAL_TR" "ACCEPTANCE CRITERIA
  - [ ] AC-1 (mechanical): the gate is category-blind. Check: \`pytest -q tests/unit\` -> expects 0 failures.
Write it into src/screening/prompts/guidance.json")" \
  "refused source path re-routed to the test-author blocks"
expect_allow \
  "$(lane_builder "$REFUSAL_TR" "Change src/screening/prompts/guidance.json")" \
  "refused source path routed to the builder allows"
expect_allow \
  "$(agent_json_with_transcript executor "$REFUSAL_TR" "$NOTHING_WRITTEN
Install the dependencies")" \
  "unrelated dispatch after a refusal is untouched"

# A refused DOC path belongs to the scribe, so the same rule points the other way.
DOC_REFUSAL_TR="$(write_refusal_transcript "docs/STATUS-task.md")"
expect_block \
  "$(lane_builder "$DOC_REFUSAL_TR" "Write docs/STATUS-task.md")" \
  "refused doc path re-routed to the builder blocks"

# --- A WRONG REFUSAL MUST BE ESCAPABLE, AND ONLY BY THE HUMAN.
# On 2026-08-04 the lane guard refused an architect its own plan for what turned out to
# be a guard defect. This rule then made that false refusal routing law: five attempts,
# no way out, because a refusal was treated as necessarily correct. The escape is the
# human's, in the human's own turn — never the orchestrator's.
REROUTE_PROMPT="$NOTHING_WRITTEN
Apply the fix to src/screening/prompts/guidance.json and land it"

OVERRIDE_TR="$(write_refusal_transcript "src/screening/prompts/guidance.json")"
append_human_turn "$OVERRIDE_TR" \
  "That refusal was a guard defect, not a routing error.
WORKFORCE_OVERRIDE: lane-refusal | src/screening/prompts/guidance.json"
expect_allow "$(agent_json_with_transcript executor "$OVERRIDE_TR" "$REROUTE_PROMPT")" \
  "a human override in the human's own turn releases the refused path"

OTHER_TR="$(write_refusal_transcript "src/screening/prompts/guidance.json")"
append_human_turn "$OTHER_TR" "WORKFORCE_OVERRIDE: lane-refusal | docs/OTHER.md"
expect_block "$(agent_json_with_transcript executor "$OTHER_TR" "$REROUTE_PROMPT")" \
  "an override naming a different path does not release this one"

AGENT_TR="$(write_refusal_transcript "src/screening/prompts/guidance.json")"
append_assistant_turn "$AGENT_TR" \
  "The refusal looks wrong to me, so:
WORKFORCE_OVERRIDE: lane-refusal | src/screening/prompts/guidance.json"
expect_block "$(agent_json_with_transcript executor "$AGENT_TR" "$REROUTE_PROMPT")" \
  "the orchestrator cannot override its own refusal"

SUBAGENT_TR="$(write_refusal_transcript "src/screening/prompts/guidance.json")"
append_tool_result_turn "$SUBAGENT_TR" \
  "WORKFORCE_OVERRIDE: lane-refusal | src/screening/prompts/guidance.json"
expect_block "$(agent_json_with_transcript executor "$SUBAGENT_TR" "$REROUTE_PROMPT")" \
  "a subagent's report cannot carry the override"

# The guard's own refusal text names the marker so a human can find it. That text
# reaches the transcript, so it must never be readable back as an override: it carries
# the literal placeholder, and a placeholder equals no real path.
ECHO_TR="$(write_refusal_transcript "src/screening/prompts/guidance.json")"
append_human_turn "$ECHO_TR" \
  "only your human can release a path, by writing this line in their own message:
WORKFORCE_OVERRIDE: lane-refusal | <path>
Do not write that line yourself."
expect_block "$(agent_json_with_transcript executor "$ECHO_TR" "$REROUTE_PROMPT")" \
  "the guard's own remediation text cannot be read back as an override"

# Granularity: releasing one path releases only that path.
TWO_TR="$(write_refusal_transcript "src/screening/prompts/guidance.json")"
jq -nc --arg t "WORKFORCE_REFUSAL: out-of-lane | docs/STATUS-task.md" \
  '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_ref_2",content:[{type:"text",text:$t}]}]}}' \
  >> "$TWO_TR"
append_human_turn "$TWO_TR" "WORKFORCE_OVERRIDE: lane-refusal | src/screening/prompts/guidance.json"
expect_block \
  "$(agent_json_with_transcript executor "$TWO_TR" "$NOTHING_WRITTEN
Apply the fix to src/screening/prompts/guidance.json and also write docs/STATUS-task.md")" \
  "a second refused path with no override still blocks the dispatch"

# --- A PATH NO LANE COVERS IS NOT AUTOMATICALLY THE BUILDER'S.
# 2026-08-04: the agent memory, at <home>/.claude/projects/<project>/memory, is outside every
# checkout. The scribe was refused it; this guard's fallback — "nothing claims it, so
# it is source, so it is the builder's" — then sent it to the one role confined to a
# git worktree, which refused it too. The fallback holds INSIDE the working tree, where
# unclaimed really does mean source, and must not invent an owner outside it.
MEM_HOME="$WORK/home"
MEM_DIR="$MEM_HOME/.claude/projects/-Users-someone-project/memory"
mkdir -p "$MEM_DIR" "$MEM_HOME/notes"

expect_home() { # $1 expected rc $2 payload $3 label
  local rc out
  out="$(printf '%s' "$2" | HOME="$MEM_HOME" bash "$GUARD" 2>&1)"
  rc=$?
  if [ "$rc" -eq "$1" ]; then
    pass_case "$3"
  else
    fail_case "$3" "expected exit $1; observed exit=$rc out=$out"
  fi
}
allow_home() { expect_home 0 "$1" "$2"; }
block_home() { expect_home 2 "$1" "$2"; }

MEM_LESSON="$MEM_DIR/feedback-never-bury-open-items.md"
MEM_TR="$(write_refusal_transcript "$MEM_LESSON")"
allow_home \
  "$(agent_json_cwd scribe "$MEM_TR" "Write the lesson to $MEM_LESSON" "$LANE_PROJ")" \
  "a refused memory path routed to the scribe, whose lane covers it, allows"
block_home \
  "$(lane_builder "$MEM_TR" "Write $MEM_LESSON")" \
  "a refused memory path routed to the builder still blocks"

# A path outside the tree that NO lane covers: re-routing cannot fix it, so the guard
# says so instead of naming a role that would be refused in turn.
LOOSE="$MEM_HOME/notes/loose.md"
LOOSE_TR="$(write_refusal_transcript "$LOOSE")"
block_home "$(lane_builder "$LOOSE_TR" "Write $LOOSE")" \
  "an unowned path outside the working tree is not handed to the builder"
LOOSE_PAYLOAD="$(agent_json_cwd executor "$LOOSE_TR" "$NOTHING_WRITTEN
Write $LOOSE" "$LANE_PROJ")"
block_home "$LOOSE_PAYLOAD" \
  "an unowned path outside the working tree is not handed to the executor either"
LOOSE_MSG="$(printf '%s' "$LOOSE_PAYLOAD" | HOME="$MEM_HOME" bash "$GUARD" 2>&1 >/dev/null)"
case "$LOOSE_MSG" in
  *"outside this project's working tree"*) pass_case "the refusal says the path is outside the working tree" ;;
  *) fail_case "the refusal says the path is outside the working tree" "observed: $LOOSE_MSG" ;;
esac
case "$LOOSE_MSG" in
  *"belongs to the builder"*) fail_case "the refusal does not name the builder as owner" "observed: $LOOSE_MSG" ;;
  *) pass_case "the refusal does not name the builder as owner" ;;
esac

# --- A RELEASE COVERS THE DIRECTORY IT NAMES.
# The human is reading a refusal that names one file and releasing the directory the
# work belongs in — the exact line this guard's own remediation text invites. Exact
# string equality made that line silently do nothing.
DIR_TR="$(write_refusal_transcript "$MEM_LESSON")"
append_human_turn "$DIR_TR" "That directory is mine to release.
WORKFORCE_OVERRIDE: lane-refusal | $MEM_DIR/"
allow_home \
  "$(agent_json_cwd executor "$DIR_TR" "$NOTHING_WRITTEN
Write $MEM_LESSON" "$LANE_PROJ")" \
  "releasing a directory releases a file beneath it"
OTHER_DIR_TR="$(write_refusal_transcript "$MEM_LESSON")"
append_human_turn "$OTHER_DIR_TR" "WORKFORCE_OVERRIDE: lane-refusal | $MEM_HOME/notes/"
block_home \
  "$(agent_json_cwd executor "$OTHER_DIR_TR" "$NOTHING_WRITTEN
Write $MEM_LESSON" "$LANE_PROJ")" \
  "releasing a different directory does not release this path"

# An override is a control that stopped enforcing, so it is recorded as loudly as a
# block — a fail-open nobody counted is indistinguishable from a rule nobody needed.
printf '%s' "$(agent_json_with_transcript executor "$OVERRIDE_TR" "$REROUTE_PROMPT")" \
  | bash "$GUARD" >/dev/null 2>&1
OVERRIDE_LINE=""
[ -f "$GUARD_LOG" ] && OVERRIDE_LINE="$(jq -rc \
  'select(.verdict == "fail-open" and (.detail | test("guidance.json")))' "$GUARD_LOG" \
  2>/dev/null | tail -n1)"
if [ -n "$OVERRIDE_LINE" ]; then
  pass_case "an override is recorded as a fail-open naming the released path"
else
  fail_case "an override is recorded as a fail-open naming the released path" \
    "observed no such record in $GUARD_LOG"
fi
