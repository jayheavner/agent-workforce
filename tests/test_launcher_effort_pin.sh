#!/usr/bin/env bash
# tests/test_launcher_effort_pin.sh — the launcher pins the session effort.
#
# Live incident 2026-07-29: the profile-wide `effortLevel` in settings.json is
# applied to every session, and the orchestrator's frontmatter `effort:` never
# reached the main session — transcript evidence showed opus-4-8 orchestrator
# sessions running at `medium` while the role declares `high`, and plain
# opus-5 sessions running at `xhigh`. `xhigh` is rejected outright by the API
# when extended thinking is off ("effort 'xhigh' is not supported when
# thinking is disabled on this model"), and the rejection lands on the first
# request, so the session is dead on arrival. The launcher therefore passes
# the role's declared effort on the command line, where it is authoritative.
#
# `claude` is stubbed on PATH and the launcher runs with --no-install, so
# nothing is fetched, installed, or written outside this test's sandbox.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/launcher-effort-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# claude stub: record the invocation, never launch anything.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "claude-stub: $*" >> "${CLAUDE_STUB_LOG:?}"
exit 0
EOF
chmod +x "$TMP/bin/claude"

SANDBOX_HOME="$TMP/home"
mkdir -p "$SANDBOX_HOME"
run_launcher() { # $1 launcher dir (repo root), $2 log label, rest: launcher args
  local repo="$1" label="$2"; shift 2
  CLAUDE_STUB_LOG="$TMP/$label.log" \
  HOME="$SANDBOX_HOME" \
  CLAUDE_CONFIG_DIR="$TMP/profile-$label" \
  PATH="$TMP/bin:$PATH" \
  bash "$repo/bin/agent-workforce" --no-install "$@" 2> "$TMP/$label.stderr"
}

# The effort the orchestrator role declares — read here independently of the
# launcher so the test fails if the two ever disagree.
DECLARED="$(awk '/^---$/{n++; if (n==2) exit} n==1 && /^effort:/{
  sub(/^effort:[[:space:]]*/, ""); print; exit}' "$ROOT/agents/orchestrator.md")"
[ -n "$DECLARED" ] \
  && pass "orchestrator.md declares an effort ($DECLARED)" \
  || fail "orchestrator.md declares an effort"

# --- (a) snapshot mode passes the declared effort ----------------------------
run_launcher "$ROOT" a
INVOKE="$(cat "$TMP/a.log" 2>/dev/null || true)"
case "$INVOKE" in
  *"--effort $DECLARED"*) pass "snapshot launch pins --effort $DECLARED" ;;
  *) fail "snapshot launch pins --effort $DECLARED — got: $INVOKE" ;;
esac
case "$INVOKE" in
  *"--agent orchestrator"*) pass "snapshot launch still starts the orchestrator" ;;
  *) fail "snapshot launch still starts the orchestrator — got: $INVOKE" ;;
esac

# --- (b) a caller's own --effort comes later and therefore wins --------------
run_launcher "$ROOT" b --effort max
INVOKE_B="$(cat "$TMP/b.log" 2>/dev/null || true)"
LAUNCHER_POS="${INVOKE_B%%--effort $DECLARED*}"
CALLER_POS="${INVOKE_B%%--effort max*}"
if [ "${#CALLER_POS}" -gt "${#LAUNCHER_POS}" ]; then
  pass "caller's --effort is passed after the launcher's pin"
else
  fail "caller's --effort is passed after the launcher's pin — got: $INVOKE_B"
fi

# --- (c) plugin mode pins the same effort -----------------------------------
run_launcher "$ROOT" c --plugin
INVOKE_C="$(cat "$TMP/c.log" 2>/dev/null || true)"
case "$INVOKE_C" in
  *"--effort $DECLARED"*) pass "plugin launch pins --effort $DECLARED" ;;
  *) fail "plugin launch pins --effort $DECLARED — got: $INVOKE_C" ;;
esac

# --- (d) an unusable declaration warns and falls back, never passes garbage —
# Minimal fixture: only the files the launcher touches on the --no-install path.
FAKE="$TMP/repo"
mkdir -p "$FAKE/bin" "$FAKE/agents" "$FAKE/hooks"
cp "$ROOT/bin/agent-workforce" "$FAKE/bin/"
cp "$ROOT/hooks/cost_report.py" "$FAKE/hooks/" 2>/dev/null || true
sed "s/^effort:.*/effort: turbo/" "$ROOT/agents/orchestrator.md" > "$FAKE/agents/orchestrator.md"
if run_launcher "$FAKE" d; then
  pass "unknown declared effort still launches (soft failure)"
else
  fail "unknown declared effort still launches — stderr: $(cat "$TMP/d.stderr")"
fi
INVOKE_D="$(cat "$TMP/d.log" 2>/dev/null || true)"
case "$INVOKE_D" in
  *"--effort"*) fail "unknown effort must not be passed through — got: $INVOKE_D" ;;
  *) pass "unknown effort is not passed through" ;;
esac
grep -q "effort" "$TMP/d.stderr" \
  && pass "unknown effort is named on stderr" \
  || fail "unknown effort is named on stderr — $(cat "$TMP/d.stderr")"

# --- (e) a missing declaration also falls back softly ------------------------
sed "/^effort:/d" "$ROOT/agents/orchestrator.md" > "$FAKE/agents/orchestrator.md"
if run_launcher "$FAKE" e; then
  pass "absent declared effort still launches (soft failure)"
else
  fail "absent declared effort still launches — stderr: $(cat "$TMP/e.stderr")"
fi
INVOKE_E="$(cat "$TMP/e.log" 2>/dev/null || true)"
case "$INVOKE_E" in
  *"--effort"*) fail "absent effort must not pass an empty flag — got: $INVOKE_E" ;;
  *) pass "absent effort passes no flag" ;;
esac

echo "launcher effort-pin tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
