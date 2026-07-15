#!/usr/bin/env bash
# tests/test_plugin_mode.sh — validate live checkout loading and hook routing.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
ROUTER="$REPO/hooks/agent-team-plugin-router.sh"
TMPDIR_T="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_T"' EXIT

PASS=0
FAIL=0
RC=0

ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

expect_rc() { # $1 expected, $2 mode, $3 json, $4 label
  set +e
  printf '%s' "$3" | AGENT_TEAM_AUDIT_LOG="$TMPDIR_T/audit.log" \
    AGENT_TEAM_COST_DIR="$TMPDIR_T/cost" bash "$ROUTER" "$2" >/dev/null 2>&1
  RC=$?
  set -u
  [ "$RC" -eq "$1" ] && ok || bad "$4 (expected $1, got $RC)"
}

for file in .claude-plugin/plugin.json settings.json hooks/hooks.json; do
  jq empty "$REPO/$file" >/dev/null 2>&1 && ok || bad "$file is not valid JSON"
done

bash -n "$REPO/bin/agent-workforce" "$ROUTER" \
  && ok || bad "plugin launcher or router failed bash -n"

[ "$(jq -r '.name' "$REPO/.claude-plugin/plugin.json")" = "agent-workforce" ] \
  && ok || bad "plugin manifest name is not agent-workforce"
[ "$(jq -r '.agent' "$REPO/settings.json")" = "agent-workforce:orchestrator" ] \
  && ok || bad "plugin settings do not select the namespaced live orchestrator"

if jq -e '
    .hooks.PreToolUse[].hooks[].command,
    .hooks.PostToolUse[].hooks[].command
    | contains("${CLAUDE_PLUGIN_ROOT}")
  ' "$REPO/hooks/hooks.json" >/dev/null; then
  ok
else
  bad "a plugin hook command does not resolve through CLAUDE_PLUGIN_ROOT"
fi

if command -v claude >/dev/null 2>&1; then
  # The repo also carries .claude-plugin/marketplace.json for ChatGPT's
  # legacy-compatible marketplace discovery. Validate the Claude plugin
  # manifest explicitly so the CLI does not choose the marketplace file.
  claude plugin validate --strict "$REPO/.claude-plugin/plugin.json" >/dev/null 2>&1 \
    && ok || bad "claude plugin validate --strict failed"
fi

bash_payload() { # $1 role, $2 command
  jq -cn --arg r "$1" --arg c "$2" \
    '{agent_type:$r,tool_name:"Bash",tool_input:{command:$c}}'
}
agent_payload() { # $1 role, $2 subagent type
  jq -cn --arg r "$1" --arg t "$2" \
    '{agent_type:$r,tool_name:"Agent",tool_input:{subagent_type:$t}}'
}

expect_rc 2 policy "$(bash_payload builder 'sam deploy')" \
  "builder policy was not enforced in plugin mode"
expect_rc 2 policy "$(bash_payload 'agent-workforce:builder' 'sam deploy')" \
  "namespaced builder role was not normalized"
expect_rc 2 policy "$(bash_payload 'agent-workforce:debugger' 'touch nope')" \
  "namespaced debugger role was not normalized"
expect_rc 0 policy "$(bash_payload unrelated-agent 'sam deploy')" \
  "plugin policy leaked into an unrelated agent"
expect_rc 0 policy "$(bash_payload 'other-plugin:builder' 'sam deploy')" \
  "plugin policy normalized a foreign plugin role"
expect_rc 2 policy '{' "malformed hook input did not fail closed"

expect_rc 2 dispatch "$(agent_payload orchestrator general-purpose)" \
  "orchestrator dispatch guard was not enforced"
expect_rc 0 dispatch "$(agent_payload 'agent-workforce:orchestrator' 'agent-workforce:builder')" \
  "namespaced orchestrator could not dispatch a namespaced specialist"
expect_rc 0 dispatch "$(agent_payload builder general-purpose)" \
  "dispatch guard leaked into a specialist"
expect_rc 0 dispatch "$(agent_payload unrelated-agent general-purpose)" \
  "dispatch guard leaked into an unrelated agent"

SID='11111111-1111-1111-1111-111111111111'
TRANSCRIPT="$TMPDIR_T/session.jsonl"
touch "$TRANSCRIPT"
COST_PAYLOAD="$(jq -cn --arg sid "$SID" --arg transcript "$TRANSCRIPT" \
  '{agent_type:"orchestrator",tool_name:"Agent",session_id:$sid,transcript_path:$transcript,cwd:"/tmp/plugin-test",tool_response:{agentId:"a",agentType:"builder"}}')"
expect_rc 0 cost "$COST_PAYLOAD" "orchestrator cost router returned an error"
find "$TMPDIR_T/cost" -type f -name "*--$SID.json" -print -quit 2>/dev/null | grep -q . \
  && ok || bad "orchestrator cost router did not invoke cost accounting"

# Exercise the launcher without starting a Claude session or requiring auth.
mkdir -p "$TMPDIR_T/fake-bin"
cat > "$TMPDIR_T/fake-bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
cat > "$TMPDIR_T/fake-bin/jq" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMPDIR_T/fake-bin/claude" "$TMPDIR_T/fake-bin/jq"
LAUNCH_ARGS="$(PATH="$TMPDIR_T/fake-bin:$PATH" bash "$REPO/bin/agent-workforce" --agent builder --help)"
EXPECTED="$(printf '%s\n' --plugin-dir "$REPO" --agent builder --help)"
[ "$LAUNCH_ARGS" = "$EXPECTED" ] && ok || bad "launcher did not pass plugin directory and user arguments exactly"

printf 'plugin-mode tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
