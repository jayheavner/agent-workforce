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
agent_payload() { # $1 role, $2 subagent type [$3 prompt]
  jq -cn --arg r "$1" --arg t "$2" --arg p "${3:-}" \
    '{agent_type:$r,tool_name:"Agent",tool_input:{subagent_type:$t,prompt:$p}}'
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
expect_rc 0 dispatch "$(agent_payload 'agent-workforce:orchestrator' 'agent-workforce:builder' 'Build it.
ACCEPTANCE CRITERIA
- [ ] AC-1 (mechanical): widget renders. Check: `python3 -m pytest tests/test_widget.py || echo "why: widget test failed"` -> expects exit 0.')" \
  "namespaced orchestrator could not dispatch a namespaced specialist"
expect_rc 2 dispatch "$(agent_payload 'agent-workforce:orchestrator' 'agent-workforce:builder' 'Build it.')" \
  "builder dispatch without ACCEPTANCE CRITERIA was not blocked in plugin mode"
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
  '{agent_type:"orchestrator",tool_name:"Agent",session_id:$sid,transcript_path:$transcript,cwd:"/tmp/plugin-test",tool_response:{agentId:"a",agentType:"builder",status:"completed",content:[{type:"text",text:"Built.\n\nWORKFORCE_REPORT: builder | complete"}]}}')"
expect_rc 0 cost "$COST_PAYLOAD" "orchestrator cost router returned an error"
find "$TMPDIR_T/cost" -type f -name "*--$SID.json" -print -quit 2>/dev/null | grep -q . \
  && ok || bad "orchestrator cost router did not invoke cost accounting"

# SubagentStop route: a workforce specialist ending without the report marker
# is blocked (Stop-decision JSON); a compliant or foreign subagent passes.
SUBSTOP_BAD="$(jq -cn '{agent_type:"builder",stop_hook_active:false,last_assistant_message:"partial work and"}')"
OUT="$(printf '%s' "$SUBSTOP_BAD" | bash "$ROUTER" subagent-stop 2>/dev/null)"
printf '%s' "$OUT" | jq -e '.decision == "block"' >/dev/null 2>&1 \
  && ok || bad "subagent-stop route did not block a marker-less specialist report"
SUBSTOP_GOOD="$(jq -cn '{agent_type:"agent-workforce:builder",stop_hook_active:false,last_assistant_message:"Done.\n\nWORKFORCE_REPORT: builder | complete"}')"
expect_rc 0 subagent-stop "$SUBSTOP_GOOD" "subagent-stop route blocked a compliant report"
expect_rc 0 subagent-stop "$(jq -cn '{agent_type:"other-plugin:builder",stop_hook_active:false,last_assistant_message:"x"}')" \
  "subagent-stop route policed a foreign plugin subagent"

# A sync result with no WORKFORCE_REPORT marker is an interrupted agent: the
# route exits 2 (reconcile-and-resume fed back) but cost accounting still runs.
rm -f "$TMPDIR_T/cost/"*"--$SID.json" 2>/dev/null
TRUNCATED_PAYLOAD="$(jq -cn --arg sid "$SID" --arg transcript "$TRANSCRIPT" \
  '{agent_type:"orchestrator",tool_name:"Agent",session_id:$sid,transcript_path:$transcript,cwd:"/tmp/plugin-test",tool_response:{agentId:"a",agentType:"builder",status:"completed",content:[{type:"text",text:"Made progress on"}]}}')"
expect_rc 2 cost "$TRUNCATED_PAYLOAD" "truncated dispatch did not fire the interrupt guard through the cost route"
find "$TMPDIR_T/cost" -type f -name "*--$SID.json" -print -quit 2>/dev/null | grep -q . \
  && ok || bad "cost accounting skipped when the interrupt guard fired"

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

# Snapshot mode (the default) launches the orchestrator in bypassPermissions
# (2026-07-19 decision) with user args AFTER the default flag, so a
# caller-supplied --permission-mode wins.
LAUNCH_ARGS="$(CLAUDE_CONFIG_DIR="$TMPDIR_T/profile" PATH="$TMPDIR_T/fake-bin:$PATH" \
  bash "$REPO/bin/agent-workforce" --no-install --help)"
EXPECTED="$(printf '%s\n' --agent orchestrator --permission-mode bypassPermissions --help)"
[ "$LAUNCH_ARGS" = "$EXPECTED" ] && ok || bad "snapshot launcher did not launch the orchestrator with user arguments exactly"

# Legacy live plugin mode still routes through --plugin-dir.
LAUNCH_ARGS="$(CLAUDE_CONFIG_DIR="$TMPDIR_T/profile" PATH="$TMPDIR_T/fake-bin:$PATH" \
  bash "$REPO/bin/agent-workforce" --plugin --agent builder --help)"
EXPECTED="$(printf '%s\n' --plugin-dir "$REPO" --agent builder --help)"
[ "$LAUNCH_ARGS" = "$EXPECTED" ] && ok || bad "plugin launcher did not pass plugin directory and user arguments exactly"

# Hook-health: a broken hook script in the profile is reported on stderr both
# BEFORE launch and AFTER the session exits (the fullscreen TUI wipes
# pre-launch output; the post-exit line is the one that stays visible), while
# stdout (the launch args) stays byte-exact.
BROKEN_PROFILE="$TMPDIR_T/broken-profile"
mkdir -p "$BROKEN_PROFILE/hooks"
printf '#!/bin/sh\nexit 0\n' > "$BROKEN_PROFILE/hooks/dead-gate.sh"   # no exec bit
HH_ERR="$(CLAUDE_CONFIG_DIR="$BROKEN_PROFILE" PATH="$TMPDIR_T/fake-bin:$PATH" \
  bash "$REPO/bin/agent-workforce" --no-install --help 2>&1 >/dev/null)"
if [ "$(printf '%s\n' "$HH_ERR" | grep -c "chmod +x $BROKEN_PROFILE/hooks/dead-gate.sh")" -eq 2 ]; then
  ok
else
  bad "launcher did not report the broken hook on stderr before AND after the session"
fi
HH_OUT="$(CLAUDE_CONFIG_DIR="$BROKEN_PROFILE" PATH="$TMPDIR_T/fake-bin:$PATH" \
  bash "$REPO/bin/agent-workforce" --no-install --help 2>/dev/null)"
EXPECTED="$(printf '%s\n' --agent orchestrator --permission-mode bypassPermissions --help)"
[ "$HH_OUT" = "$EXPECTED" ] && ok || bad "hook-health reporting leaked into launcher stdout"

# The launcher preserves the session's exit code now that claude is no longer
# exec'd (the post-exit health report runs after it returns).
mkdir -p "$TMPDIR_T/failing-bin"
cat > "$TMPDIR_T/failing-bin/claude" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
chmod +x "$TMPDIR_T/failing-bin/claude"
cp "$TMPDIR_T/fake-bin/jq" "$TMPDIR_T/failing-bin/jq"
chmod +x "$TMPDIR_T/failing-bin/jq"
CLAUDE_CONFIG_DIR="$TMPDIR_T/profile" PATH="$TMPDIR_T/failing-bin:$PATH" \
  bash "$REPO/bin/agent-workforce" --no-install >/dev/null 2>&1
[ "$?" -eq 7 ] && ok || bad "launcher did not preserve the session exit code"

printf 'plugin-mode tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
