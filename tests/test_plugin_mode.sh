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
    .hooks[][] .hooks[].command
    | contains("${CLAUDE_PLUGIN_ROOT}")
  ' "$REPO/hooks/hooks.json" >/dev/null; then
  ok
else
  bad "a plugin hook command does not resolve through CLAUDE_PLUGIN_ROOT"
fi

# The redesigned hooks.json routes exactly: secrets + dispatch (PreToolUse),
# audit + cost (PostToolUse), closeout-stop (Stop). The retired
# closeout-dispatch / closeout-subagent routes must not reappear.
jq -e '
  ([.hooks.PreToolUse[].hooks[].command] | (any(endswith(" secrets")) and any(endswith(" dispatch")))) and
  ([.hooks.PostToolUse[].hooks[].command] | (any(endswith(" audit")) and any(endswith(" cost")))) and
  ([.hooks.Stop[].hooks[].command] | any(endswith(" closeout-stop")))
' "$REPO/hooks/hooks.json" >/dev/null 2>&1 \
  && ok || bad "plugin does not register secrets, dispatch, audit, cost, and Stop closeout routes"
jq -e '
  [.hooks[][] .hooks[].command]
  | any(contains("closeout-dispatch") or contains("closeout-subagent"))
' "$REPO/hooks/hooks.json" >/dev/null 2>&1 \
  && bad "plugin still registers retired closeout-dispatch/closeout-subagent routes" || ok

python3 -c 'compile(open("hooks/agent_team_closeout.py", encoding="utf-8").read(), "hooks/agent_team_closeout.py", "exec")' \
  && ok || bad "closeout hook failed Python syntax validation"

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

expect_rc 0 secrets "$(bash_payload builder 'sam deploy')" \
  "command with no secret was blocked (blocklists are retired)"
expect_rc 2 secrets "$(bash_payload builder 'echo $OKTA_TOKEN > creds.txt')" \
  "builder secrets guard was not enforced in plugin mode"
expect_rc 2 secrets "$(bash_payload 'agent-workforce:builder' 'echo $OKTA_TOKEN > creds.txt')" \
  "namespaced builder role was not normalized"
expect_rc 2 secrets "$(bash_payload 'agent-workforce:executor' 'echo $MY_API_KEY | tee out')" \
  "namespaced executor role was not normalized"
expect_rc 0 secrets "$(bash_payload unrelated-agent 'echo $OKTA_TOKEN > creds.txt')" \
  "plugin secrets guard leaked into an unrelated agent"
expect_rc 0 secrets "$(bash_payload 'other-plugin:builder' 'echo $OKTA_TOKEN > creds.txt')" \
  "plugin secrets guard normalized a foreign plugin role"
expect_rc 2 secrets '{' "malformed hook input did not fail closed"
expect_rc 0 audit "$(bash_payload executor 'npm install left-pad')" "audit route errored"
grep -q "role=executor ran=npm install left-pad" "$TMPDIR_T/audit.log" \
  && ok || bad "audit route did not log the executor command"

expect_rc 2 dispatch "$(agent_payload orchestrator general-purpose)" \
  "orchestrator dispatch guard was not enforced"
expect_rc 0 dispatch "$(agent_payload 'agent-workforce:orchestrator' 'agent-workforce:builder')" \
  "namespaced orchestrator could not dispatch a namespaced specialist"
expect_rc 0 dispatch "$(agent_payload builder general-purpose)" \
  "dispatch guard leaked into a specialist"
expect_rc 0 dispatch "$(agent_payload unrelated-agent general-purpose)" \
  "dispatch guard leaked into an unrelated agent"

expect_rc 0 closeout-stop "$(jq -cn --arg cwd "$TMPDIR_T" '{session_id:"none",cwd:$cwd,last_assistant_message:"ordinary"}')" \
  "closeout Stop router errored for a session with no active workforce task"

SID='11111111-1111-1111-1111-111111111111'
TRANSCRIPT="$TMPDIR_T/session.jsonl"
touch "$TRANSCRIPT"
COST_PAYLOAD="$(jq -cn --arg sid "$SID" --arg transcript "$TRANSCRIPT" \
  '{agent_type:"orchestrator",tool_name:"Agent",session_id:$sid,transcript_path:$transcript,cwd:"/tmp/plugin-test",tool_response:{agentId:"a",agentType:"builder"}}')"
expect_rc 0 cost "$COST_PAYLOAD" "orchestrator cost router returned an error"
find "$TMPDIR_T/cost" -type f -name "*--$SID.json" -print -quit 2>/dev/null | grep -q . \
  && ok || bad "orchestrator cost router did not invoke cost accounting"

# Exercise the launcher without starting a Claude session, requiring auth, or
# installing into any real profile (--no-install skips the freshness check;
# CLAUDE_CONFIG_DIR points at a throwaway profile as belt and braces).
mkdir -p "$TMPDIR_T/fake-bin" "$TMPDIR_T/profile"
cat > "$TMPDIR_T/fake-bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
cat > "$TMPDIR_T/fake-bin/jq" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMPDIR_T/fake-bin/claude" "$TMPDIR_T/fake-bin/jq"

# Snapshot mode (the default) launches the orchestrator with user args intact.
LAUNCH_ARGS="$(CLAUDE_CONFIG_DIR="$TMPDIR_T/profile" PATH="$TMPDIR_T/fake-bin:$PATH" \
  bash "$REPO/bin/agent-workforce" --no-install --help)"
EXPECTED="$(printf '%s\n' --agent orchestrator --help)"
[ "$LAUNCH_ARGS" = "$EXPECTED" ] && ok || bad "snapshot launcher did not launch the orchestrator with user arguments exactly"

# Legacy live plugin mode still routes through --plugin-dir.
LAUNCH_ARGS="$(CLAUDE_CONFIG_DIR="$TMPDIR_T/profile" PATH="$TMPDIR_T/fake-bin:$PATH" \
  bash "$REPO/bin/agent-workforce" --plugin --agent builder --help)"
EXPECTED="$(printf '%s\n' --plugin-dir "$REPO" --agent builder --help)"
[ "$LAUNCH_ARGS" = "$EXPECTED" ] && ok || bad "plugin launcher did not pass plugin directory and user arguments exactly"

printf 'plugin-mode tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
