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

# --- Task 3: builder ---
expect_allow builder "$(bash_json 'sam build')" "builder: sam build allows"
expect_block builder "$(bash_json 'sam deploy --guided')" "builder: sam deploy blocks"
expect_block builder "$(bash_json 'aws s3 ls')" "builder: any aws blocks"
expect_block builder "$(bash_json 'cdk deploy')" "builder: cdk blocks"
expect_block builder "$(bash_json 'terraform apply')" "builder: terraform blocks"
expect_block builder "$(bash_json 'amplify push')" "builder: amplify blocks"
expect_block builder "$(bash_json 'git push origin main')" "builder: push to main blocks"
expect_block builder "$(bash_json 'git push origin master')" "builder: push to master blocks"
expect_block builder "$(bash_json 'git push')" "builder: bare push blocks"
expect_allow builder "$(bash_json 'git push origin feature/hooks')" "builder: push to feature branch allows"
expect_allow builder "$(bash_json 'git commit -m x && pytest -q')" "builder: commit and test allows"

# --- Task 4: verifier/reviewer ---
expect_allow verifier "$(bash_json 'pytest tests/ -v')" "verifier: test run allows"
expect_allow verifier "$(bash_json 'npm test')" "verifier: npm test allows"
expect_allow reviewer "$(bash_json 'git diff main...HEAD')" "reviewer: git diff allows"
expect_allow reviewer "$(bash_json 'git log --oneline')" "reviewer: git log allows"
expect_block verifier "$(bash_json 'aws s3 rm s3://bucket/key')" "verifier: cloud blocks"
expect_block verifier "$(bash_json 'rm -rf build/')" "verifier: rm blocks"
expect_block verifier "$(bash_json 'echo fixed > src/app.py')" "verifier: redirect to file blocks"
expect_block verifier "$(bash_json 'sed -i "" "s/a/b/" src/app.py')" "verifier: in-place sed blocks"
expect_block reviewer "$(bash_json 'git commit -m looks-good')" "reviewer: git commit blocks"
expect_block reviewer "$(bash_json 'git checkout -- .')" "reviewer: git checkout blocks"
expect_block verifier "$(bash_json 'pip install requests')" "verifier: package install blocks"
expect_block reviewer "$(bash_json 'sam deploy')" "reviewer: deploy toolchain blocks"

# --- Task 3: git push refspec bypass hardening ---
expect_block builder "$(bash_json 'git push origin main:main')" "builder: refspec main:main blocks"
expect_block builder "$(bash_json 'git push origin HEAD:main')" "builder: refspec HEAD:main blocks"
expect_block builder "$(bash_json 'git push origin HEAD:master')" "builder: refspec HEAD:master blocks"
expect_block builder "$(bash_json 'git push origin refs/heads/main')" "builder: fully-qualified refs/heads/main blocks"
expect_block builder "$(bash_json 'git push origin refs/heads/master')" "builder: fully-qualified refs/heads/master blocks"
expect_allow builder "$(bash_json 'git push origin feature/main')" "builder: feature/main path segment allows"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
