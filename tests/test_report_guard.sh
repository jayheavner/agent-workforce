#!/usr/bin/env bash
# tests/test_report_guard.sh — verifies the specialist-side Stop/SubagentStop
# report guard: a specialist whose final message lacks the WORKFORCE_REPORT
# marker in its last three non-empty lines is blocked from stopping (JSON
# {"decision":"block"} on stdout, exit 0 — the harness Stop-decision shape) so
# it must emit its report contract before it may finish. Covers async
# dispatches: the guard runs at the specialist's own stop, regardless of how
# the parent consumes the result. Fail-open paths: stop_hook_active (never
# block twice), unparseable input, missing jq.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
GUARD="$HERE/../hooks/agent-team-report-guard.sh"
PASS=0
FAIL=0
RC=0
OUT=""

run() { # $1 input
  set +e
  OUT="$(printf '%s' "$1" | bash "$GUARD" 2>/dev/null)"
  RC=$?
  set -u
}

expect_allow() { # $1 input, $2 label
  run "$1"
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL [$2]: rc=$RC out=$OUT"
  fi
}

expect_block() { # $1 input, $2 label
  run "$1"
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1)); echo "FAIL [$2]: rc=$RC out=$OUT"
  fi
}

payload() { # $1 last_assistant_message, $2 stop_hook_active, $3 agent_type
  jq -cn --arg m "$1" --argjson a "$2" --arg t "$3" \
    '{session_id:"s1",stop_hook_active:$a,last_assistant_message:$m,agent_type:$t}'
}

GOOD='Built the widget. Tests: 4 passed.

WORKFORCE_REPORT: builder | complete'

# Marker in final lines -> allow.
expect_allow "$(payload "$GOOD" false builder)" "marker present allows"

# Marker above a Codex profile final line -> allow.
CODEX='Done.
WORKFORCE_REPORT: builder | partial
WORKFORCE_PROFILE: agent_workforce_builder | gpt-5.6-sol | high'
expect_allow "$(payload "$CODEX" false builder)" "marker above profile line allows"

# No marker -> block with the contract in the reason.
run "$(payload 'Made progress on the middleware and' false builder)"
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | jq -e '.decision == "block" and (.reason | contains("WORKFORCE_REPORT"))' >/dev/null 2>&1; then
  PASS=$((PASS+1))
else
  FAIL=$((FAIL+1)); echo "FAIL [missing marker blocks with contract]: rc=$RC out=$OUT"
fi

# Marker quoted mid-message but not in the tail -> block.
MID='The dispatch requires WORKFORCE_REPORT: builder | complete at the end.
Progress so far: 3 of 9.
More.
Even more.
Final line without it.'
expect_block "$(payload "$MID" false builder)" "mid-message marker still blocks"

# stop_hook_active -> always allow (never block twice; never wedge).
expect_allow "$(payload 'no marker here' true builder)" "stop_hook_active allows"

# Empty / absent message -> allow (nothing to police; the parent-side
# consumption checks own that case).
expect_allow "$(jq -cn '{session_id:"s1",stop_hook_active:false,agent_type:"builder"}')" "absent message allows"

# Garbage input -> allow (advisory fail-open).
expect_allow 'not json' "malformed stdin allows"
expect_allow '' "empty stdin allows"

echo "report-guard tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
