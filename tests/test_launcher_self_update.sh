#!/usr/bin/env bash
# tests/test_launcher_self_update.sh — the launcher's origin freshness check.
#
# Decision 2026-07-22: a stale clone self-certifies as fresh (needs_install
# compares profile vs local tree only), so the launcher must check origin and
# fast-forward before installing. These tests run the REAL launcher end to end
# against a local bare origin, with `claude` stubbed on PATH; every failure
# path must be soft (offline / diverged never blocks a launch) and the
# remaining deficit must be recorded for the cost-report stamp.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/launcher-update-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# --- fixture: seed repo from the CURRENT working tree, bare origin, checkout —
SEED="$TMP/seed"
mkdir -p "$SEED"
# rsync the working tree (not HEAD) so the launcher under test is this one.
rsync -a --exclude ".git" "$ROOT/" "$SEED/" >/dev/null 2>&1
git -C "$SEED" init -q -b main
git -C "$SEED" config user.email test@example.invalid
git -C "$SEED" config user.name "Launcher Test"
git -C "$SEED" add -A
git -C "$SEED" commit -qm "test: seed A"
git clone -q --bare "$SEED" "$TMP/origin.git"
git clone -q "$TMP/origin.git" "$TMP/checkout"
git -C "$TMP/checkout" config user.email test@example.invalid
git -C "$TMP/checkout" config user.name "Launcher Test"
# advance origin past the checkout: seed gains commit B and pushes.
git -C "$SEED" remote add origin "$TMP/origin.git"
echo "b" > "$SEED/UPDATE-MARKER.txt"
git -C "$SEED" add UPDATE-MARKER.txt
git -C "$SEED" commit -qm "test: seed B"
git -C "$SEED" push -q origin main

# claude stub: record the invocation, never launch anything.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "claude-stub: $*" >> "${CLAUDE_STUB_LOG:?}"
exit 0
EOF
chmod +x "$TMP/bin/claude"

run_launcher() { # $1 checkout dir, $2 profile dir, $3 log label
  CLAUDE_STUB_LOG="$TMP/$3.log" \
  CLAUDE_CONFIG_DIR="$2" \
  PATH="$TMP/bin:$PATH" \
  bash "$1/bin/agent-workforce" 2> "$TMP/$3.stderr"
}

# --- (a) behind + clean -> fast-forwards, installs, launches, behind=0 ------
if run_launcher "$TMP/checkout" "$TMP/profile-a" a; then
  pass "behind+clean launch exits 0"
else
  fail "behind+clean launch exits 0 — stderr: $(cat "$TMP/a.stderr")"
fi
grep -q "fast-forwarding" "$TMP/a.stderr" \
  && pass "stale checkout announces the fast-forward" \
  || fail "stale checkout announces the fast-forward — $(cat "$TMP/a.stderr")"
[ -f "$TMP/checkout/UPDATE-MARKER.txt" ] \
  && pass "checkout actually advanced to origin's commit" \
  || fail "checkout actually advanced to origin's commit"
if jq -e '.behind == 0' "$TMP/profile-a/agent-team-origin-status.json" >/dev/null 2>&1; then
  pass "origin-status records behind=0 after update"
else
  fail "origin-status records behind=0 after update"
fi
grep -q "claude-stub" "$TMP/a.log" \
  && pass "launch proceeded after update" \
  || fail "launch proceeded after update"

# --- (b) behind + diverged -> warns, does not touch history, records deficit —
git -C "$SEED" commit -q --allow-empty -m "test: seed C"
git -C "$SEED" push -q origin main
echo "local" > "$TMP/checkout/LOCAL-DIVERGENCE.txt"
git -C "$TMP/checkout" add LOCAL-DIVERGENCE.txt
git -C "$TMP/checkout" commit -qm "test: local divergence"
BEFORE="$(git -C "$TMP/checkout" rev-parse HEAD)"
if run_launcher "$TMP/checkout" "$TMP/profile-b" b; then
  pass "diverged launch still exits 0 (soft failure)"
else
  fail "diverged launch still exits 0 — stderr: $(cat "$TMP/b.stderr")"
fi
grep -q "local changes or divergence" "$TMP/b.stderr" \
  && pass "diverged checkout warns instead of merging" \
  || fail "diverged checkout warns instead of merging — $(cat "$TMP/b.stderr")"
[ "$(git -C "$TMP/checkout" rev-parse HEAD)" = "$BEFORE" ] \
  && pass "diverged checkout history untouched" \
  || fail "diverged checkout history untouched"
if jq -e '.behind >= 1' "$TMP/profile-b/agent-team-origin-status.json" >/dev/null 2>&1; then
  pass "origin-status records the remaining deficit"
else
  fail "origin-status records the remaining deficit"
fi

# --- (c) unreachable origin -> soft warning, still launches ------------------
git -C "$TMP/checkout" remote set-url origin "$TMP/does-not-exist.git"
if run_launcher "$TMP/checkout" "$TMP/profile-c" c; then
  pass "offline launch exits 0"
else
  fail "offline launch exits 0 — stderr: $(cat "$TMP/c.stderr")"
fi
grep -q "could not reach origin" "$TMP/c.stderr" \
  && pass "unreachable origin warns softly" \
  || fail "unreachable origin warns softly — $(cat "$TMP/c.stderr")"
grep -q "claude-stub" "$TMP/c.log" \
  && pass "launch proceeded despite unreachable origin" \
  || fail "launch proceeded despite unreachable origin"

# --- (d) --no-install skips the origin check entirely ------------------------
if CLAUDE_STUB_LOG="$TMP/d.log" CLAUDE_CONFIG_DIR="$TMP/profile-d" \
   PATH="$TMP/bin:$PATH" \
   bash "$TMP/checkout/bin/agent-workforce" --no-install 2> "$TMP/d.stderr"; then
  pass "--no-install launch exits 0"
else
  fail "--no-install launch exits 0 — stderr: $(cat "$TMP/d.stderr")"
fi
if grep -q "could not reach origin\|fast-forwarding" "$TMP/d.stderr"; then
  fail "--no-install must skip the origin check — $(cat "$TMP/d.stderr")"
else
  pass "--no-install skips the origin check"
fi

echo "launcher self-update tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
