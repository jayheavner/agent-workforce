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

echo "dispatch-guard tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
