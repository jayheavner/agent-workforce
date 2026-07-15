#!/usr/bin/env bash
# tests/test_secrets_hook.sh — the single blocking rule (approve-intent spec):
# a credential-bearing variable directed at a file blocks; everything else runs.
# Ports the secret-guard cases from the retired policy suite.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../hooks/agent-team-secrets.sh"
SCRATCH="$(mktemp -d)"
export AGENT_TEAM_AUDIT_LOG="$SCRATCH/audit.log"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL [$1]"; }

bash_payload() { jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}'; }
write_payload() { jq -cn --arg f "$1" --arg c "$2" '{tool_name:"Write", tool_input:{file_path:$f, content:$c}}'; }
run() { set +e; printf '%s' "$1" | bash "$HOOK" "$2" >/dev/null 2>&1; RC=$?; set -u; }

# Secret variable directed at a file: redirect and tee both block (exit 2).
run "$(bash_payload 'echo $OKTA_TOKEN > creds.txt')" builder
[ "$RC" -eq 2 ] && ok || no "secret redirect to file blocks"
run "$(bash_payload 'printf %s ${MY_API_KEY} | tee out.txt')" executor
[ "$RC" -eq 2 ] && ok || no "secret piped to tee blocks"
run "$(bash_payload 'echo $DB_PASSWORD >> .env.backup')" ops
[ "$RC" -eq 2 ] && ok || no "secret append-redirect blocks"

# Secret WITHOUT file direction: allowed — using a credential is normal work.
run "$(bash_payload 'curl -H "Authorization: Bearer $SOME_API_KEY" https://api.example.com')" ops
[ "$RC" -eq 0 ] && ok || no "secret used in a command (no file direction) allows"

# /dev/null and fd-dup redirects are not file writes: no false positive.
run "$(bash_payload 'aws sts get-caller-identity --token $AWS_SECRET_ACCESS_KEY 2>/dev/null')" ops
[ "$RC" -eq 0 ] && ok || no "2>/dev/null does not false-positive"
run "$(bash_payload 'deploy_thing $GODADDY_API_SECRET 2>&1')" deployer
[ "$RC" -eq 0 ] && ok || no "2>&1 does not false-positive"
run "$(bash_payload 'run_tests $BUILD_NUMBER 2>&1 > results.txt')" builder
[ "$RC" -eq 0 ] && ok || no "non-credential variable with redirect allows"

# Write/Edit content carrying a credential-variable reference blocks; plain allows.
run "$(write_payload docs/notes.md 'export OKTA_TOKEN=$OKTA_TOKEN')" scribe
[ "$RC" -eq 2 ] && ok || no "file content referencing a credential variable blocks"
run "$(write_payload docs/notes.md 'ordinary documentation text')" scribe
[ "$RC" -eq 0 ] && ok || no "plain file content allows"

# Blocks are logged to the audit log.
grep -q "decision=block" "$AGENT_TEAM_AUDIT_LOG" && ok || no "blocks are audited"

# Codex parity: a pinned expected model blocks on mismatch, allows on match.
set +e
printf '%s' "$(jq -cn '{model:"gpt-other", tool_name:"Bash", tool_input:{command:"echo hi"}}')" \
  | AGENT_TEAM_EXPECTED_MODEL="gpt-5.6-terra" bash "$HOOK" builder >/dev/null 2>&1; RC=$?
set -u
[ "$RC" -eq 2 ] && ok || no "expected-model mismatch blocks"
set +e
printf '%s' "$(jq -cn '{model:"gpt-5.6-terra", tool_name:"Bash", tool_input:{command:"echo hi"}}')" \
  | AGENT_TEAM_EXPECTED_MODEL="gpt-5.6-terra" bash "$HOOK" builder >/dev/null 2>&1; RC=$?
set -u
[ "$RC" -eq 0 ] && ok || no "expected-model match allows"

# Fail-open plumbing: non-write tools, malformed stdin, missing role all exit 0.
run '{"tool_name":"Read","tool_input":{"file_path":"x"}}' reviewer
[ "$RC" -eq 0 ] && ok || no "non-write tool allows"
run 'not json at all' builder
[ "$RC" -eq 0 ] && ok || no "malformed stdin fails open"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
