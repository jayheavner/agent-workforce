#!/usr/bin/env bash
# tests/test_dispatch_guard.sh — verifies the PreToolUse(Agent) dispatch guard.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/../hooks/agent-team-dispatch-guard.sh"
PASS=0
FAIL=0
RC=0

run() { # $1 json
  set +e
  printf '%s' "$1" | bash "$GUARD" >/dev/null 2>&1
  RC=$?
  set -u
}

agent_json() { jq -cn --arg t "$1" '{tool_name:"Agent",tool_input:{subagent_type:$t}}'; }

# Build a fixture transcript with one unresolved Agent tool_use for the named
# subagent_type (T6: serialize-mutating-dispatches ground truth).
write_unresolved_transcript() { # $1 subagent_type -> prints path
  local role="$1"
  local path
  path="$(mktemp "${TMPDIR:-/tmp}/dispatch-guard-transcript.XXXXXX")"
  jq -cn --arg role "$role" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_fixture_serialize_1",name:"Agent",input:{subagent_type:$role}}]}}' \
    > "$path"
  printf '%s' "$path"
}

agent_json_with_transcript() { # $1 subagent_type $2 transcript_path $3 prompt
  jq -cn --arg t "$1" --arg tp "$2" --arg p "$3" \
    '{tool_name:"Agent",transcript_path:$tp,tool_input:{subagent_type:$t,prompt:$p}}'
}

# Build a fixture transcript with N resolved (paired) Agent dispatches, for
# T12's budget-ratchet ground truth: count = all Agent dispatches, resolved
# or not, regardless of role.
write_resolved_dispatches_transcript() { # $1 count -> prints path
  local count="$1"
  local path
  path="$(mktemp "${TMPDIR:-/tmp}/dispatch-guard-budget.XXXXXX")"
  : > "$path"
  local i=0
  while [ "$i" -lt "$count" ]; do
    jq -cn --arg id "toolu_budget_$i" \
      '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Agent",input:{subagent_type:"scribe"}}]}}' \
      >> "$path"
    jq -cn --arg id "toolu_budget_$i" \
      '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:[{type:"text",text:"done"}]}]}}' \
      >> "$path"
    i=$((i + 1))
  done
  printf '%s' "$path"
}

expect() { # $1 expected_rc, $2 json, $3 label
  run "$2"
  if [ "$RC" -eq "$1" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL [$3]: expected=$1 got=$RC"
  fi
}
expect_allow() { expect 0 "$1" "$2"; }
expect_block() { expect 2 "$1" "$2"; }

# All ten valid specialists allow.
for a in architect builder debugger verifier reviewer deployer researcher ops scribe ticketer; do
  expect_allow "$(agent_json "$a")" "valid: $a allows"
  expect_allow "$(agent_json "agent-workforce:$a")" "valid plugin namespace: $a allows"
done

# Missing / empty / harness-default / unknown all block.
expect_block "$(jq -cn '{tool_name:"Agent",tool_input:{description:"do a thing"}}')" "missing subagent_type blocks"
expect_block "$(agent_json '')" "empty subagent_type blocks"
expect_block "$(agent_json 'general-purpose')" "general-purpose blocks"
expect_block "$(agent_json 'designer')" "unknown type blocks"
expect_block "$(agent_json 'other-plugin:builder')" "foreign plugin namespace blocks"

# Substring of a valid name must NOT match (space-delimited membership).
expect_block "$(agent_json 'archi')" "substring 'archi' blocks"
expect_block "$(agent_json 'build')" "substring 'build' blocks"

# A non-Agent tool passes through untouched.
expect_allow "$(jq -cn '{tool_name:"Bash",tool_input:{command:"ls"}}')" "non-Agent tool passes"

# Valid JSON but tool_name is not "Agent" must still pass through, even with
# an odd/absent subagent_type — only Agent dispatches are policed.
expect_allow "$(jq -cn '{tool_name:"Read",tool_input:{file_path:"/tmp/x"}}')" "valid JSON, non-Agent tool_name passes"

# Finding 1: malformed / non-JSON / empty stdin must BLOCK (fail closed),
# not be silently coerced to empty tool_name and allowed.
expect_block "not json at all" "malformed stdin blocks"
expect_block "" "empty stdin blocks"
expect_block "{" "truncated JSON blocks"

# Finding 2: compound value spanning two valid tokens must not bypass via
# substring containment against the space-padded VALID list.
expect_block "$(agent_json 'architect builder')" "compound 'architect builder' blocks"
expect_block "$(agent_json ' architect ')" "padded exact-looking value blocks"

# T6: serialize git-mutating dispatches ({builder, executor, deployer}) per
# checkout while one is unresolved, unless the new dispatch's prompt carries
# the exact PARALLEL_SAFE marker.
BUILDER_TRANSCRIPT="$(write_unresolved_transcript builder)"

expect_block \
  "$(agent_json_with_transcript executor "$BUILDER_TRANSCRIPT" "run the finalizer")" \
  "unresolved builder blocks executor without marker"

expect_allow \
  "$(agent_json_with_transcript executor "$BUILDER_TRANSCRIPT" "PARALLEL_SAFE: no git mutation in this dispatch")" \
  "unresolved builder allows executor with PARALLEL_SAFE marker"

# Background dispatch: builder tool_use answered only by a launch STUB — the
# dispatch is still in flight, so a second mutating dispatch must serialize.
write_bg_stub_transcript() { # $1 subagent_type [$2 with_notification] -> prints path
  local path
  path="$(mktemp "${TMPDIR:-/tmp}/dispatch-guard-transcript.XXXXXX")"
  jq -nc --arg role "$1" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_bg_1",name:"Agent",input:{subagent_type:$role}}]}}' \
    >"$path"
  jq -nc \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_bg_1",content:[{type:"text",text:"Async agent launched successfully. agentId: abc"}]}]}}' \
    >>"$path"
  if [ "${2:-}" = "with_notification" ]; then
    jq -nc \
      '{type:"user",message:{role:"user",content:[{type:"text",text:"<task-notification>\n<tool-use-id>toolu_bg_1</tool-use-id>\n<status>completed</status>\n</task-notification>"}]}}' \
      >>"$path"
  fi
  printf '%s' "$path"
}

BG_STUB_TRANSCRIPT="$(write_bg_stub_transcript builder)"
expect_block \
  "$(agent_json_with_transcript executor "$BG_STUB_TRANSCRIPT" "run the finalizer")" \
  "background builder (launch stub only) still serializes"

BG_DONE_TRANSCRIPT="$(write_bg_stub_transcript builder with_notification)"
expect_allow \
  "$(agent_json_with_transcript executor "$BG_DONE_TRANSCRIPT" "run the finalizer")" \
  "background builder resolved by task-notification allows"

rm -f "$BG_STUB_TRANSCRIPT" "$BG_DONE_TRANSCRIPT"

NO_MUTATING_TRANSCRIPT="$(write_unresolved_transcript researcher)"
expect_allow \
  "$(agent_json_with_transcript executor "$NO_MUTATING_TRANSCRIPT" "run the finalizer")" \
  "no unresolved serialized dispatch allows"

rm -f "$BUILDER_TRANSCRIPT" "$NO_MUTATING_TRANSCRIPT"

# T12: dispatch-count budget ratchet. Default checkpoint 10 (from
# hooks/agent-team-budgets.json). This is the incoming dispatch: transcript
# holds N PRIOR dispatches, and the guard evaluates the (N+1)th attempt.
NINE_PRIOR="$(write_resolved_dispatches_transcript 9)"
expect_block \
  "$(agent_json_with_transcript scribe "$NINE_PRIOR" "write the status note")" \
  "10th dispatch attempt without ack blocks at checkpoint 10"

expect_allow \
  "$(agent_json_with_transcript scribe "$NINE_PRIOR" "WORKFORCE_BUDGET_ACK: 10 dispatches — continuing because standard-tier route mid-build")" \
  "10th dispatch attempt with WORKFORCE_BUDGET_ACK allows"

TEN_PRIOR="$(write_resolved_dispatches_transcript 10)"
expect_allow \
  "$(agent_json_with_transcript scribe "$TEN_PRIOR" "write the status note")" \
  "11th dispatch attempt (past the 10th) without ack allows"

EIGHTEEN_PRIOR="$(write_resolved_dispatches_transcript 18)"
expect_allow \
  "$(agent_json_with_transcript scribe "$EIGHTEEN_PRIOR" "write the status note")" \
  "19th dispatch attempt without ack allows (next checkpoint is 20)"

rm -f "$NINE_PRIOR" "$TEN_PRIOR" "$EIGHTEEN_PRIOR"

# --- roster drift: the guard allowlist, agents/, and the orchestrator's
# Agent(...) tools must name exactly the same specialists, or a grown agent
# silently becomes undispatchable (three-touchpoint rule in growing-the-team).
GUARD_ROSTER="$(grep '^readonly VALID_SPECIALISTS=' "$GUARD" | sed 's/.*"\(.*\)".*/\1/' | tr ' ' '\n' | sort)"
AGENT_ROSTER="$(cd "$HERE/../agents" && ls *.md | sed 's/\.md$//' | grep -v '^orchestrator$' | sort)"
ORCH_ROSTER="$(grep -o 'Agent([a-z-]*)' "$HERE/../agents/orchestrator.md" | sed 's/Agent(\(.*\))/\1/' | sort -u)"
if [ "$GUARD_ROSTER" = "$AGENT_ROSTER" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1)); echo "FAIL [roster]: guard VALID_SPECIALISTS != agents/*.md"
fi
if [ "$ORCH_ROSTER" = "$AGENT_ROSTER" ]; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1)); echo "FAIL [roster]: orchestrator Agent(...) != agents/*.md"
fi

echo "dispatch-guard tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
