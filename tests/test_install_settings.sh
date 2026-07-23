#!/usr/bin/env bash
# tests/test_install_settings.sh — installer-owned settings rules + the
# session-start hook reaching the profile.
#
# 2026-07-22: the memory-write permission fix was first shipped as a
# paste-this-doc instruction; Jay correctly called that fog-of-war debt. The
# installer now owns it: rules merged idempotently into the profile's
# settings.json on every install, so a machine three months from now gets
# them with zero human memory involved.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-settings-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"   # macOS TMPDIR ends in '/', which would leave a
                            # double slash the merge normalizes away
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# Hooks install into $HOME/.claude/hooks (frontmatter paths are fixed to it);
# sandbox HOME so the suite never touches the real machine.
SANDBOX_HOME="$TMP/home"
mkdir -p "$SANDBOX_HOME"
PROFILE="$TMP/profile"
mkdir -p "$PROFILE"
# Pre-existing settings the merge must preserve untouched.
jq -n '{model: "claude-opus-4-8", permissions: {allow: ["Bash(ls:*)"]}}' \
  > "$PROFILE/settings.json"

AGENT_TEAM_SKIP_INSTALL_TEST=1 HOME="$SANDBOX_HOME" bash "$REPO/install.sh" --profile "$PROFILE" \
  > "$TMP/install.log" 2>&1 \
  && pass "install exits 0" \
  || fail "install exits 0 — $(tail -3 "$TMP/install.log")"

S="$PROFILE/settings.json"
# 2026-07-22: Claude Code file-permission checks match Edit(path) rules only;
# a Write(path) rule is dead config that warns at every session start. The
# installer must plant Edit only, and remove the Write rule it used to plant.
jq -e --arg r "Write(/$PROFILE/projects/**/memory/**)" \
  '.permissions.allow | index($r) | not' "$S" >/dev/null 2>&1 \
  && pass "dead Write rule for the memory dirs is NOT merged" \
  || fail "dead Write rule for the memory dirs is NOT merged — $(cat "$S")"
jq -e --arg r "Edit(/$PROFILE/projects/**/memory/**)" \
  '.permissions.allow | index($r)' "$S" >/dev/null 2>&1 \
  && pass "Edit rule for the memory dirs is merged" \
  || fail "Edit rule for the memory dirs is merged"
jq -e '.permissions.allow | index("Bash(ls:*)")' "$S" >/dev/null 2>&1 \
  && pass "pre-existing allow rules survive the merge" \
  || fail "pre-existing allow rules survive the merge"
jq -e '.model == "claude-opus-4-8"' "$S" >/dev/null 2>&1 \
  && pass "unrelated settings keys survive the merge" \
  || fail "unrelated settings keys survive the merge"

COUNT_BEFORE="$(jq '.permissions.allow | length' "$S")"
AGENT_TEAM_SKIP_INSTALL_TEST=1 HOME="$SANDBOX_HOME" bash "$REPO/install.sh" --profile "$PROFILE" \
  > /dev/null 2>&1
COUNT_AFTER="$(jq '.permissions.allow | length' "$S")"
[ "$COUNT_BEFORE" = "$COUNT_AFTER" ] \
  && pass "re-install adds no duplicate rules (idempotent)" \
  || fail "re-install adds no duplicate rules — $COUNT_BEFORE -> $COUNT_AFTER"

# A profile with NO settings.json gets one containing exactly the Edit rule.
PROFILE2="$TMP/profile2"
mkdir -p "$PROFILE2"
AGENT_TEAM_SKIP_INSTALL_TEST=1 HOME="$SANDBOX_HOME" bash "$REPO/install.sh" --profile "$PROFILE2" \
  > /dev/null 2>&1
jq -e '.permissions.allow | length == 1' "$PROFILE2/settings.json" >/dev/null 2>&1 \
  && pass "fresh profile gets a settings.json with exactly the Edit rule" \
  || fail "fresh profile gets a settings.json with exactly the Edit rule — $(cat "$PROFILE2/settings.json")"

# A profile carrying the dead Write rule from an earlier install has it
# removed on re-install; unrelated rules survive the cleanup.
PROFILE4="$TMP/profile4"
mkdir -p "$PROFILE4"
jq -n --arg w "Write(/$TMP/profile4/projects/**/memory/**)" \
  '{permissions: {allow: [$w, "Bash(ls:*)"]}}' > "$PROFILE4/settings.json"
AGENT_TEAM_SKIP_INSTALL_TEST=1 HOME="$SANDBOX_HOME" bash "$REPO/install.sh" --profile "$PROFILE4" \
  > /dev/null 2>&1
jq -e --arg w "Write(/$TMP/profile4/projects/**/memory/**)" \
  '.permissions.allow | index($w) | not' "$PROFILE4/settings.json" >/dev/null 2>&1 \
  && pass "stale Write rule from a prior install is removed" \
  || fail "stale Write rule from a prior install is removed — $(cat "$PROFILE4/settings.json")"
jq -e '.permissions.allow | index("Bash(ls:*)")' "$PROFILE4/settings.json" >/dev/null 2>&1 \
  && pass "unrelated rules survive the stale-rule cleanup" \
  || fail "unrelated rules survive the stale-rule cleanup"

# The session-start hook must actually reach the profile (it is referenced by
# the orchestrator frontmatter; a missing file would fail hook health).
[ -f "$SANDBOX_HOME/.claude/hooks/session_start.py" ] \
  && pass "session_start.py is installed into the hooks dir" \
  || fail "session_start.py is installed into the hooks dir"
jq -e '.files["hooks/session_start.py"]' "$PROFILE/agent-team-manifest.json" >/dev/null 2>&1 \
  && pass "session_start.py is recorded in the manifest" \
  || fail "session_start.py is recorded in the manifest"

# --- delete guard: installer-owned, never a paste-this instruction ---------
# 2026-07-22 (Jay): "We've talked about pasting shit manually. NO." The rm/
# worktree delete guard ships with install: binary into the hooks dir, wiring
# merged into the profile settings, idempotent across re-installs.
GUARD="$SANDBOX_HOME/.claude/hooks/auto-approve-safe-deletes.py"
[ -x "$GUARD" ] \
  && pass "delete guard is installed into the hooks dir and executable" \
  || fail "delete guard is installed into the hooks dir and executable"
jq -e --arg g "$GUARD" \
  '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?
    | select(.command | contains($g))] | length == 1' "$S" >/dev/null 2>&1 \
  && pass "delete-guard PreToolUse wiring is merged into settings.json" \
  || fail "delete-guard PreToolUse wiring is merged into settings.json — $(cat "$S")"
AGENT_TEAM_SKIP_INSTALL_TEST=1 HOME="$SANDBOX_HOME" bash "$REPO/install.sh" --profile "$PROFILE" \
  > /dev/null 2>&1
jq -e --arg g "$GUARD" \
  '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?
    | select(.command | contains($g))] | length == 1' "$S" >/dev/null 2>&1 \
  && pass "re-install does not duplicate the delete-guard wiring" \
  || fail "re-install does not duplicate the delete-guard wiring"
# A pre-existing MANUAL wiring (another path) is never touched, but the
# canonical entry is still ensured: manual entries may carry an rm-only
# matcher filter that would blind the guard to git deletions.
PROFILE3="$TMP/profile3"
mkdir -p "$PROFILE3"
jq -n '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command",
  command: "python3 /somewhere/else/auto-approve-safe-deletes.py"}]}]}}' \
  > "$PROFILE3/settings.json"
AGENT_TEAM_SKIP_INSTALL_TEST=1 HOME="$SANDBOX_HOME" bash "$REPO/install.sh" --profile "$PROFILE3" \
  > /dev/null 2>&1
jq -e '[.. | strings | select(contains("/somewhere/else/auto-approve-safe-deletes.py"))] | length == 1' \
  "$PROFILE3/settings.json" >/dev/null 2>&1 \
  && pass "pre-existing manual guard wiring survives untouched" \
  || fail "pre-existing manual guard wiring survives untouched"
jq -e --arg g "$GUARD" \
  '[.hooks.PreToolUse[]? | .hooks[]? | select(.command | contains($g))] | length == 1' \
  "$PROFILE3/settings.json" >/dev/null 2>&1 \
  && pass "canonical guard wiring is added alongside manual wiring" \
  || fail "canonical guard wiring is added alongside manual wiring — $(cat "$PROFILE3/settings.json")"

echo "install-settings tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
