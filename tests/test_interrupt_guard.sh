#!/usr/bin/env bash
# tests/test_interrupt_guard.sh — verifies the PostToolUse(Agent) interrupt
# guard: a sync dispatch result whose report does not end with a
# WORKFORCE_REPORT marker line is treated as an interrupted agent (exit 2,
# reconcile-and-resume guidance on stderr). Advisory guard: fails OPEN on
# unparseable input, and never fires on async launch stubs or non-Agent tools.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/../hooks/agent-team-interrupt-guard.sh"
PASS=0
FAIL=0
RC=0
ERR=""

run() { # $1 json-or-garbage
  set +e
  ERR="$(printf '%s' "$1" | bash "$GUARD" 2>&1 >/dev/null)"
  RC=$?
  set -u
}

expect() { # $1 expected_rc, $2 input, $3 label
  run "$2"
  if [ "$RC" -eq "$1" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL [$3]: expected=$1 got=$RC"
  fi
}

expect_stderr_has() { # $1 needle, $2 label
  case "$ERR" in
    *"$1"*) PASS=$((PASS+1)) ;;
    *) FAIL=$((FAIL+1)); echo "FAIL [$2]: stderr missing '$1' — got: $ERR" ;;
  esac
}

# result_json ROLE STATUS TEXT -> PostToolUse payload with content as an
# array of text blocks (the shape verified on real transcripts).
result_json() {
  jq -cn --arg t "$1" --arg s "$2" --arg x "$3" \
    '{tool_name:"Agent",tool_input:{subagent_type:$t},
      tool_response:{agentId:"a1",agentType:$t,status:$s,content:[{type:"text",text:$x}]}}'
}

COMPLETE_REPORT='Built the widget.

Tests: 4 passed.

WORKFORCE_REPORT: builder | complete'

# Marker on the final line -> allow.
expect 0 "$(result_json builder completed "$COMPLETE_REPORT")" "marker on final line allows"

# Marker within the last three non-empty lines (Codex profile line after) -> allow.
CODEX_REPORT='Built the widget.

WORKFORCE_REPORT: builder | partial

WORKFORCE_PROFILE: agent_workforce_builder | gpt-5.6-sol | high'
expect 0 "$(result_json builder completed "$CODEX_REPORT")" "marker above profile final line allows"

# No marker -> exit 2, guidance names RESUME and interruption.
expect 2 "$(result_json builder completed 'Made progress on C4, running tests now')" "missing marker fires"
expect_stderr_has "RESUME" "missing-marker stderr carries RESUME protocol"
expect_stderr_has "interrupted" "missing-marker stderr names interruption"

# Marker quoted mid-report but absent from the tail is NOT a report ending.
MIDQUOTE='The dispatch said to end with WORKFORCE_REPORT: builder | complete
but I am still working.
Progress: 3 of 9 tasks.
More lines.
Even more lines.'
expect 2 "$(result_json builder completed "$MIDQUOTE")" "marker only mid-report still fires"

# Async launch stub (status async_launched, isAsync, no content) -> allow;
# completion arrives later as a task-notification.
ASYNC_STUB="$(jq -cn '{tool_name:"Agent",tool_input:{subagent_type:"builder"},
  tool_response:{agentId:"a2",isAsync:true,status:"async_launched",outputFile:"/tmp/x"}}')"
expect 0 "$ASYNC_STUB" "async launch stub allows"

# Non-Agent tools pass through.
expect 0 "$(jq -cn '{tool_name:"Bash",tool_response:{stdout:"ok"}}')" "non-Agent tool allows"

# Advisory guard fails OPEN on garbage: it cannot undo the call, only inform.
expect 0 "not json" "malformed stdin allows (advisory, fail-open)"
expect 0 "" "empty stdin allows"

# Defensive: content as a plain string instead of block array is still honored.
STRING_CONTENT="$(jq -cn '{tool_name:"Agent",tool_input:{subagent_type:"scribe"},
  tool_response:{agentId:"a3",status:"completed",content:"Note written.\n\nWORKFORCE_REPORT: scribe | complete"}}')"
expect 0 "$STRING_CONTENT" "string content with marker allows"

STRING_NO_MARKER="$(jq -cn '{tool_name:"Agent",tool_input:{subagent_type:"scribe"},
  tool_response:{agentId:"a3",status:"completed",content:"Half a note about"}}')"
expect 2 "$STRING_NO_MARKER" "string content without marker fires"

echo "interrupt-guard tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
