#!/usr/bin/env bash
# tests/test_install_shim.sh — the `agent-workforce` command shim.
#
# 2026-07-26 (Jay, test machine): started the team with `claude --agent
# orchestrator` — the intuitive command, taught by the README and the
# installer's own closing message — and got a silently degraded session (no
# bypassPermissions, no freshness check). The fix is one obvious command:
# the installer ships an `agent-workforce` shim onto PATH that execs the
# repo launcher, and stops recommending the raw claude invocation anywhere.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-shim-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

SANDBOX_HOME="$TMP/home"
mkdir -p "$SANDBOX_HOME"
PROFILE="$TMP/profile"
mkdir -p "$PROFILE"

AGENT_TEAM_SKIP_INSTALL_TEST=1 HOME="$SANDBOX_HOME" bash "$REPO/install.sh" --profile "$PROFILE" \
  > "$TMP/install.log" 2>&1 \
  && pass "install exits 0" \
  || fail "install exits 0 — $(tail -3 "$TMP/install.log")"

SHIM="$SANDBOX_HOME/.local/bin/agent-workforce"
[ -x "$SHIM" ] \
  && pass "shim installed executable at ~/.local/bin/agent-workforce" \
  || fail "shim installed executable at ~/.local/bin/agent-workforce"
grep -q "$REPO/bin/agent-workforce" "$SHIM" 2>/dev/null \
  && pass "shim execs this repo's launcher" \
  || fail "shim execs this repo's launcher"

# The shim forwards args and env to the real launcher. Stub claude/jq so the
# launcher runs without a real session; --no-install skips the freshness pass.
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\n' > "$TMP/bin/claude"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/jq"
chmod +x "$TMP/bin/claude" "$TMP/bin/jq"
OUT="$(CLAUDE_CONFIG_DIR="$PROFILE" PATH="$TMP/bin:$PATH" "$SHIM" --no-install --help 2>/dev/null)"
EXPECTED="$(printf '%s\n' --agent orchestrator --permission-mode bypassPermissions --help)"
[ "$OUT" = "$EXPECTED" ] \
  && pass "shim launch is byte-identical to the repo launcher's" \
  || fail "shim launch is byte-identical to the repo launcher's — got: $OUT"

# Sandbox HOME's ~/.local/bin is never on PATH, so the installer must say so.
grep -qi "not on PATH" "$TMP/install.log" \
  && pass "installer warns when the shim dir is not on PATH" \
  || fail "installer warns when the shim dir is not on PATH"

# The closing message must teach the shim, never the raw claude invocation
# (that command silently drops bypassPermissions and the freshness check).
grep -q "claude --agent orchestrator" "$TMP/install.log" \
  && fail "installer no longer recommends raw 'claude --agent orchestrator'" \
  || pass "installer no longer recommends raw 'claude --agent orchestrator'"
grep -Eq 'start the team with: (CLAUDE_CONFIG_DIR="[^"]*" )?agent-workforce$' "$TMP/install.log" \
  && pass "installer recommends the agent-workforce command" \
  || fail "installer recommends the agent-workforce command"

printf 'install-shim tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
