#!/usr/bin/env bash
# tests/test_policy_hooks.sh — executable form of the spec's hook policy.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
POLICY="$HERE/../hooks/agent-team-policy.sh"
TMPDIR_T="$(mktemp -d)"
export AGENT_TEAM_AUDIT_LOG="$TMPDIR_T/audit.log"
PASS=0
FAIL=0
RC=0

run_policy() { # $1 role, $2 json
  set +e
  printf '%s' "$2" | bash "$POLICY" "$1" >/dev/null 2>&1
  RC=$?
  set -u
}

bash_json() { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
write_json() { jq -cn --arg f "$1" '{tool_name:"Write",tool_input:{file_path:$f}}'; }

expect() { # $1 expected_rc, $2 role, $3 json, $4 label
  run_policy "$2" "$3"
  if [ "$RC" -eq "$1" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    echo "FAIL [$4]: role=$2 expected=$1 got=$RC"
  fi
}
expect_allow() { expect 0 "$1" "$2" "$3"; }
expect_block() { expect 2 "$1" "$2" "$3"; }

# --- Task 1: core dispatch ---
expect_allow builder "$(bash_json 'ls -la')" "core: benign command allows"
expect_allow reviewer "$(jq -cn '{tool_name:"Glob",tool_input:{pattern:"**/*.py"}}')" "core: non-policed tool allows"
run_policy '' "$(bash_json 'ls')"; [ "$RC" -eq 2 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [core: missing role errors]"; }
grep -q 'role=builder tool=Bash decision=allow' "$AGENT_TEAM_AUDIT_LOG" \
  && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [core: audit line written]"; }

# --- Task 2: global rules ---
expect_block builder "$(bash_json 'echo $OKTA_TOKEN > /tmp/t.txt')" "secrets: env secret redirected to file blocks"
expect_block scribe "$(bash_json 'printf "%s" "${MY_API_KEY}" | tee creds.txt')" "secrets: tee of *_API_KEY blocks"
expect_block ops "$(bash_json 'echo $NAS_PASSWORD >> notes.md')" "secrets: *_PASSWORD* redirect blocks"
expect_allow builder "$(bash_json 'export SSHPASS="$NAS_PASSWORD" && sshpass -e ssh host uptime')" "secrets: env-var use without file write allows"
expect_allow verifier "$(bash_json 'pytest -q 2>/dev/null')" "secrets: /dev/null redirect is not a file write"
expect_block builder "$(bash_json 'op read op://vault/item/credential')" "op: builder may not invoke 1Password CLI"
expect_allow ops "$(bash_json 'op read op://vault/item/credential')" "op: ops may invoke 1Password CLI"
expect_allow deployer "$(bash_json 'op read op://vault/item/credential')" "op: deployer may invoke 1Password CLI"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
