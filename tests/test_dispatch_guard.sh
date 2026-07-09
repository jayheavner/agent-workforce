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

# All nine valid specialists allow.
for a in architect builder verifier reviewer deployer researcher ops scribe ticketer; do
  expect_allow "$(agent_json "$a")" "valid: $a allows"
done

# Missing / empty / harness-default / unknown all block.
expect_block "$(jq -cn '{tool_name:"Agent",tool_input:{description:"do a thing"}}')" "missing subagent_type blocks"
expect_block "$(agent_json '')" "empty subagent_type blocks"
expect_block "$(agent_json 'general-purpose')" "general-purpose blocks"
expect_block "$(agent_json 'designer')" "unknown type blocks"

# Substring of a valid name must NOT match (space-delimited membership).
expect_block "$(agent_json 'archi')" "substring 'archi' blocks"
expect_block "$(agent_json 'build')" "substring 'build' blocks"

# A non-Agent tool passes through untouched.
expect_allow "$(jq -cn '{tool_name:"Bash",tool_input:{command:"ls"}}')" "non-Agent tool passes"

echo "dispatch-guard tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
