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

NO_MUTATING_TRANSCRIPT="$(write_unresolved_transcript researcher)"
expect_allow \
  "$(agent_json_with_transcript executor "$NO_MUTATING_TRANSCRIPT" "run the finalizer")" \
  "no unresolved serialized dispatch allows"

rm -f "$BUILDER_TRANSCRIPT" "$NO_MUTATING_TRANSCRIPT"

# T11: block researcher dispatches whose prompt asks for present-state shell
# verification; RESEARCH_ONLY exempts genuine document analysis.
prompt_json() { # $1 subagent_type $2 prompt
  jq -cn --arg t "$1" --arg p "$2" '{tool_name:"Agent",tool_input:{subagent_type:$t,prompt:$p}}'
}

expect_block \
  "$(prompt_json researcher "verify 8332d6a8 is on origin/main with git merge-base")" \
  "researcher + shell-verb prompt blocks"

expect_allow \
  "$(prompt_json researcher "verify 8332d6a8 is on origin/main with git merge-base. RESEARCH_ONLY: sources provided in prompt")" \
  "researcher + shell-verb prompt + RESEARCH_ONLY marker allows"

expect_allow \
  "$(prompt_json executor "verify 8332d6a8 is on origin/main with git merge-base")" \
  "executor + any prompt allows (unchanged)"

echo "dispatch-guard tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
