#!/usr/bin/env bash
# tests/test_audit_hook.sh — the flight recorder (approve-intent spec): PostToolUse
# on Bash appends "<ts> role=<role> ran=<command>". Always exits 0; can never block.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/agent-team-audit.sh"
SCRATCH="$(mktemp -d)"
export AGENT_TEAM_AUDIT_LOG="$SCRATCH/audit.log"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL [$1]"; }
run() { set +e; printf '%s' "$1" | bash "$HOOK" "$2" >/dev/null 2>&1; RC=$?; set -u; }

# A Bash command is logged with role and command text.
run "$(jq -cn '{tool_name:"Bash", tool_input:{command:"npm install commander"}}')" executor
[ "$RC" -eq 0 ] && ok || no "bash fire exits 0"
grep -q "role=executor ran=npm install commander" "$AGENT_TEAM_AUDIT_LOG" && ok || no "command logged with role"

# Non-Bash tools log nothing and exit 0.
BEFORE="$(wc -l < "$AGENT_TEAM_AUDIT_LOG")"
run "$(jq -cn '{tool_name:"Read", tool_input:{file_path:"x"}}')" reviewer
[ "$RC" -eq 0 ] && ok || no "non-bash exits 0"
[ "$(wc -l < "$AGENT_TEAM_AUDIT_LOG")" = "$BEFORE" ] && ok || no "non-bash logs nothing"

# Malformed stdin: exit 0, never a failure surfaced to the agent.
run 'garbage {{{' ops
[ "$RC" -eq 0 ] && ok || no "malformed stdin exits 0"

# Unwritable log destination: swallowed by design, exit 0.
AGENT_TEAM_AUDIT_LOG="/nonexistent-root-dir/audit.log" run "$(jq -cn '{tool_name:"Bash", tool_input:{command:"echo hi"}}')" builder 2>/dev/null
set +e; printf '%s' "$(jq -cn '{tool_name:"Bash", tool_input:{command:"echo hi"}}')" | AGENT_TEAM_AUDIT_LOG="/nonexistent-root-dir/audit.log" bash "$HOOK" builder >/dev/null 2>&1; RC=$?; set -u
[ "$RC" -eq 0 ] && ok || no "unwritable log dir exits 0"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
