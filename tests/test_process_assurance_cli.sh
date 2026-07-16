#!/usr/bin/env bash
# Verify the operator CLI can create and inspect durable assurance state.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/bin/agent-workforce-process-assurance"
STATE="$(mktemp -d)"
trap 'rm -rf "$STATE"' EXIT

CHARTER='{"task_id":"cli-task","version":1,"tier":"standard","objective":"Verify the operator CLI","delivery_target":"integrated code","scope":["hooks","tests"],"non_goals":["production promotion"],"acceptance_criteria":["state is durable"],"required_checkpoints":["PRE_BUILDER","PRE_CLOSEOUT"],"approved_by":"requester","approval_ref":"user-cli"}'

printf '%s' "$CHARTER" | python3 "$CLI" --state-root "$STATE" --session cli-session \
  --mode SHADOW charter-init - | grep -q '"schema":"intent-charter/1"' || {
    printf 'FAIL: charter-init did not return the durable charter\n'
    exit 1
  }

python3 "$CLI" --state-root "$STATE" --session cli-session --mode SHADOW status \
  | grep -q '"active_charter_sha256"' || {
    printf 'FAIL: status did not return the active projection\n'
    exit 1
  }

python3 "$CLI" --state-root "$STATE" --session cli-session --mode SHADOW metrics \
  | grep -q '"escaped_violations":0' || {
    printf 'FAIL: metrics did not return the effectiveness scorecard\n'
    exit 1
  }

printf 'process-assurance CLI tests: PASS=3 FAIL=0\n'
