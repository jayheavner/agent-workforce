#!/usr/bin/env bash
# tests/test_codex_profiles.sh — validate generated Codex profiles and installer behavior.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
POLICY="$REPO/codex/model-policy.json"
PROFILE_DIR="$REPO/codex/agents"
LAUNCH_PROFILE_DIR="$REPO/codex/profiles"
TMPDIR_T="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_T"' EXIT

PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

jq empty "$POLICY" >/dev/null 2>&1 && ok || bad "codex/model-policy.json is not valid JSON"

if jq -e '
  .schema_version == 1
  and .orchestrator.model == "gpt-5.6-sol"
  and .orchestrator.effort == "high"
  and (.profiles | length == 23)
  and ([.profiles[].name] | unique | length == 23)
  and ([.profiles[].name] | all(test("^[a-z0-9_]+$")))
  and ([.profiles[].role] | unique | sort == ["architect","builder","debugger","deployer","ops","researcher","reviewer","scribe","ticketer","verifier"])
  and ([.profiles[].model] | all(. == "gpt-5.6-sol" or . == "gpt-5.6-terra" or . == "gpt-5.6-luna"))
  and ([.profiles[].effort] | all(. == "low" or . == "medium" or . == "high" or . == "xhigh" or . == "max"))
  and (first(.profiles[] | select(.name == "agent_workforce_debugger")) == {
    name: "agent_workforce_debugger", role: "debugger", variant: "default",
    model: "gpt-5.6-terra", effort: "high", sandbox_mode: "read-only",
    approval_policy: "never", web_search: "disabled",
    description: "Diagnose symptoms and return evidence without applying a fix."
  })
  and (first(.profiles[] | select(.name == "agent_workforce_debugger_deep")) == {
    name: "agent_workforce_debugger_deep", role: "debugger", variant: "upshift",
    model: "gpt-5.6-sol", effort: "high", sandbox_mode: "read-only",
    approval_policy: "never", web_search: "disabled",
    description: "Perform a second diagnosis of the same symptom or diagnose a cross-system failure."
  })
' "$POLICY" >/dev/null; then
  ok
else
  bad "Codex model policy does not contain the required role and variant matrix"
fi

if python3 - "$POLICY" "$LAUNCH_PROFILE_DIR" <<'PY'
import json
import pathlib
import sys
import tomllib

policy = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
profile_dir = pathlib.Path(sys.argv[2])
for expected in policy["profiles"]:
    path = profile_dir / f'{expected["name"]}.config.toml'
    parsed = tomllib.loads(path.read_text(encoding="utf-8"))
    assert "name" not in parsed
    assert "description" not in parsed
    assert parsed["model"] == expected["model"]
    assert parsed["model_reasoning_effort"] == expected["effort"]
    assert parsed["developer_instructions"].strip()
    assert parsed["hooks"]["PreToolUse"]
    assert parsed["hooks"]["SessionStart"]
PY
then
  ok
else
  bad "a direct-launch Codex profile does not preserve its role runtime"
fi

python3 "$REPO/scripts/render_codex_agents.py" --check >/dev/null 2>&1 \
  && ok || bad "generated Codex profiles are stale"

if python3 - "$POLICY" "$PROFILE_DIR" <<'PY'
import json
import pathlib
import sys
import tomllib

policy = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
profile_dir = pathlib.Path(sys.argv[2])
for expected in policy["profiles"]:
    path = profile_dir / f'{expected["name"]}.toml'
    parsed = tomllib.loads(path.read_text(encoding="utf-8"))
    assert parsed["name"] == expected["name"]
    assert parsed["model"] == expected["model"]
    assert parsed["model_reasoning_effort"] == expected["effort"]
    assert parsed["sandbox_mode"] == expected["sandbox_mode"]
    assert parsed["approval_policy"] == expected["approval_policy"]
    assert parsed["developer_instructions"].strip()
    hooks = parsed["hooks"]["PreToolUse"]
    assert hooks and expected["role"] in hooks[0]["hooks"][0]["command"]
    assert parsed["hooks"]["SessionStart"]
PY
then
  ok
else
  bad "a generated Codex profile does not match model-policy.json"
fi

if python3 - "$POLICY" "$REPO/codex/agent-workforce.config.toml" <<'PY'
import json
import pathlib
import sys
import tomllib

policy = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
config = tomllib.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
assert config["model"] == policy["orchestrator"]["model"]
assert config["model_reasoning_effort"] == policy["orchestrator"]["effort"]
registered = {name for name in config["agents"] if name not in {"max_threads", "max_depth", "interrupt_message"}}
assert registered == {profile["name"] for profile in policy["profiles"]}
PY
then
  ok
else
  bad "orchestrator config does not register every named custom agent"
fi

CODEX_HOME="$TMPDIR_T/codex" AGENT_WORKFORCE_SKIP_MODEL_CHECK=1 \
  bash "$REPO/install-codex.sh" >/dev/null 2>&1 \
  && ok || bad "Codex profile installer failed in a clean destination"

installed_count="$(find "$TMPDIR_T/codex/agents" -type f -name 'agent_workforce_*.toml' 2>/dev/null | wc -l | tr -d ' ')"
[ "$installed_count" = "23" ] && ok || bad "Codex installer did not install all 23 profiles"
[ -f "$TMPDIR_T/codex/agent-workforce.config.toml" ] \
  && ok || bad "Codex installer did not install the orchestrator root profile"
installed_launch_count="$(find "$TMPDIR_T/codex" -maxdepth 1 -type f -name 'agent_workforce_*.config.toml' | wc -l | tr -d ' ')"
[ "$installed_launch_count" = "23" ] && ok || bad "Codex installer did not install all 23 direct-launch profiles"

bash -n "$REPO/bin/agent-workforce-codex" "$REPO/bin/agent-workforce-dispatch" \
  && ok || bad "a Codex launcher has invalid shell syntax"
grep -qF 'WORKFORCE_PROFILE:' "$REPO/bin/agent-workforce-dispatch" \
  && grep -qF -- '--profile "$PROFILE"' "$REPO/bin/agent-workforce-dispatch" \
  && ok || bad "non-interactive dispatcher does not enforce the named profile marker"

FAKE_CODEX="$TMPDIR_T/fake-codex"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -u' \
  'output=""' \
  'while [ "$#" -gt 0 ]; do' \
  '  if [ "$1" = "--output-last-message" ]; then output="$2"; shift 2; else shift; fi' \
  'done' \
  'if [ -n "${FAKE_BAD_MARKER:-}" ]; then' \
  '  printf "wrong marker\n" > "$output"' \
  'else' \
  '  printf "WORKFORCE_PROFILE: agent_workforce_reviewer | gpt-5.6-sol | high\n" > "$output"' \
  'fi' \
  'if [ -n "${AGENT_WORKFORCE_DISPATCH_AUDIT:-}" ] && [ -z "${FAKE_SKIP_AUDIT:-}" ]; then' \
  '  printf "role=reviewer tool= decision=allow detail=tool=\n" > "$AGENT_WORKFORCE_DISPATCH_AUDIT"' \
  'fi' \
  > "$FAKE_CODEX"
chmod +x "$FAKE_CODEX"

CODEX_HOME="$TMPDIR_T/codex" CODEX_BIN="$FAKE_CODEX" AGENT_WORKFORCE_SKIP_MODEL_CHECK=1 \
  bash "$REPO/bin/agent-workforce-dispatch" agent_workforce_reviewer "review fixture" >/dev/null 2>&1 \
  && ok || bad "non-interactive dispatcher rejected a matching profile marker"

if CODEX_HOME="$TMPDIR_T/codex" CODEX_BIN="$FAKE_CODEX" AGENT_WORKFORCE_SKIP_MODEL_CHECK=1 \
  FAKE_BAD_MARKER=1 bash "$REPO/bin/agent-workforce-dispatch" \
  agent_workforce_reviewer "review fixture" >/dev/null 2>&1; then
  bad "non-interactive dispatcher accepted a mismatched profile marker"
else
  ok
fi

if CODEX_HOME="$TMPDIR_T/codex" CODEX_BIN="$FAKE_CODEX" AGENT_WORKFORCE_SKIP_MODEL_CHECK=1 \
  FAKE_SKIP_AUDIT=1 bash "$REPO/bin/agent-workforce-dispatch" \
  agent_workforce_reviewer "review fixture" >/dev/null 2>&1; then
  bad "non-interactive dispatcher continued when the role hook did not run"
else
  ok
fi

CODEX_HOME="$TMPDIR_T/codex" AGENT_WORKFORCE_SKIP_MODEL_CHECK=1 \
  bash "$REPO/install-codex.sh" --check >/dev/null 2>&1 \
  && ok || bad "Codex profile install check failed"

printf 'obsolete profile fixture\n' > "$TMPDIR_T/codex/agents/agent-workforce-researcher-fast.toml"
CODEX_HOME="$TMPDIR_T/codex" AGENT_WORKFORCE_SKIP_MODEL_CHECK=1 \
  bash "$REPO/install-codex.sh" >/dev/null 2>&1 \
  && [ ! -e "$TMPDIR_T/codex/agents/agent-workforce-researcher-fast.toml" ] \
  && ok || bad "Codex installer did not retire an obsolete hyphenated profile"

codex_payload() { # $1 role, $2 model, $3 tool, $4 command-or-patch
  jq -cn --arg r "$1" --arg m "$2" --arg t "$3" --arg v "$4" '
    {
      hook_event_name:"PreToolUse",
      agent_type:$r,
      model:$m,
      tool_name:$t,
      tool_input:(if $t == "Bash" then {command:$v} else {patch:$v} end)
    }
  '
}

expect_policy_rc() { # $1 expected, $2 role, $3 model, $4 tool, $5 value, $6 label
  expected="$1"; role="$2"; model="$3"; tool="$4"; value="$5"; label="$6"
  set +e
  printf '%s' "$(codex_payload "$role" "$model" "$tool" "$value")" \
    | AGENT_TEAM_EXPECTED_MODEL="$model" AGENT_TEAM_AUDIT_LOG="$TMPDIR_T/audit.log" \
      bash "$REPO/hooks/agent-team-policy.sh" "$role" >/dev/null 2>&1
  rc=$?
  set -u
  [ "$rc" -eq "$expected" ] && ok || bad "$label (expected $expected, got $rc)"
}

expect_policy_rc 2 builder gpt-5.6-terra Bash 'aws s3 ls' \
  "Codex builder policy allowed a cloud CLI"
expect_policy_rc 2 researcher gpt-5.6-terra Bash 'pwd' \
  "Codex researcher policy allowed shell access"
expect_policy_rc 2 debugger gpt-5.6-terra Bash 'touch should-not-exist' \
  "Codex debugger policy allowed a mutating shell command"
expect_policy_rc 2 debugger gpt-5.6-terra apply_patch $'*** Begin Patch\n*** Add File: docs/should-not-exist.md\n+x\n*** End Patch' \
  "Codex debugger policy allowed a file patch"
expect_policy_rc 2 architect gpt-5.6-sol apply_patch $'*** Begin Patch\n*** Add File: src/nope.py\n+x\n*** End Patch' \
  "Codex architect policy allowed a source-code patch"
expect_policy_rc 0 architect gpt-5.6-sol apply_patch $'*** Begin Patch\n*** Add File: docs/ok.md\n+x\n*** End Patch' \
  "Codex architect policy blocked a documentation patch"

set +e
printf '%s' "$(codex_payload builder gpt-5.6-sol Bash 'pwd')" \
  | AGENT_TEAM_EXPECTED_MODEL="gpt-5.6-terra" AGENT_TEAM_AUDIT_LOG="$TMPDIR_T/audit.log" \
    bash "$REPO/hooks/agent-team-policy.sh" builder >/dev/null 2>&1
rc=$?
set -u
[ "$rc" -eq 2 ] && ok || bad "Codex policy did not fail closed on a model mismatch"

printf 'codex-profile tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
