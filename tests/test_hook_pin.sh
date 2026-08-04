#!/usr/bin/env bash
# tests/test_hook_pin.sh — a repair never changes the rules under a session that is
# already working.
#
# 2026-08-04: every hook was wired to one fixed path that the harness re-reads on
# every tool call, so installing a repair rewrote the enforcement of every live
# session mid-task. A session that had failed five times against a guard defect
# could not distinguish that from the guard being edited underneath it, and spent
# real money deciding which it was. The wired paths are now generated shims, each
# build is immutable, and a session records its build on first use and keeps it.
#
# The property under test is the one that was missing: flipping `current` must not
# change what an already-pinned session runs.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
check() { # $1 label $2 expected $3 actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 — expected '$2', got '$3'"; fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/hook-pin-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# --- a hooks dir shaped exactly like an install: the resolver, two builds, and a
# generated shim whose content does not mention either build.
HOOKS="$TMP/hooks"
VERSIONS="$HOOKS/agent-team-versions"
mkdir -p "$VERSIONS/20260804-100000-aaaaaaa" "$VERSIONS/20260804-110000-bbbbbbb"
cp "$REPO/hooks/agent-team-pin.sh" "$HOOKS/agent-team-pin.sh"
chmod +x "$HOOKS/agent-team-pin.sh"
export AGENT_TEAM_PIN_DIR="$TMP/pins"

# Two builds of one hook, distinguishable by what they print and by exit status:
# "old" refuses, "new" allows. A repair that flips behavior is the realistic case.
for spec in "20260804-100000-aaaaaaa old 2" "20260804-110000-bbbbbbb new 0"; do
  set -- $spec
  cat > "$VERSIONS/$1/probe-hook.sh" <<EOF
#!/usr/bin/env bash
payload="\$(cat)"
printf 'build=$2 role=%s payload=%s\n' "\${1:-none}" "\$payload"
exit $3
EOF
  chmod +x "$VERSIONS/$1/probe-hook.sh"
done
ln -s "20260804-100000-aaaaaaa" "$VERSIONS/current"

printf '#!/usr/bin/env bash\nHOOK_NAME="probe-hook.sh"\n. "$(dirname "$0")/agent-team-pin.sh"\n' \
  > "$HOOKS/probe-hook.sh"
chmod +x "$HOOKS/probe-hook.sh"

payload() { # $1 session id
  jq -cn --arg s "$1" '{hook_event_name:"PreToolUse",session_id:$s,tool_name:"Write"}'
}
run_shim() { # $1 session id, $2.. args -> prints output, sets RC
  local sid="$1"; shift
  set +e
  OUT="$(printf '%s' "$(payload "$sid")" | bash "$HOOKS/probe-hook.sh" "$@" 2>/dev/null)"
  RC=$?
  set -u
}

# --- the shim runs the current build, and passes through what it was given.
run_shim session-A builder
case "$OUT" in *"build=old"*) pass "shim runs the current build" ;;
  *) fail "shim runs the current build — got '$OUT'" ;; esac
check "the hook's exit status is propagated exactly" 2 "$RC"
case "$OUT" in *"role=builder"*) pass "arguments reach the pinned hook" ;;
  *) fail "arguments reach the pinned hook — got '$OUT'" ;; esac
case "$OUT" in *'"session_id":"session-A"'*) pass "stdin reaches the pinned hook intact" ;;
  *) fail "stdin reaches the pinned hook intact — got '$OUT'" ;; esac

# --- the pin is recorded on first use, naming the build actually run.
if [ -f "$AGENT_TEAM_PIN_DIR/session-A" ]; then pass "first call records a pin"; else fail "first call records a pin"; fi
check "the pin names the build that ran" "$VERSIONS/20260804-100000-aaaaaaa" \
  "$(head -n1 "$AGENT_TEAM_PIN_DIR/session-A" 2>/dev/null)"

# --- THE PROPERTY. A repair lands and flips current. The session already working
# keeps the build it started on; the next session gets the repair.
# Flipped the way the installer flips it: rename(2), which replaces the symlink
# itself. `mv` follows a symlink-to-directory destination and would move the new
# link inside the old build, leaving current aimed at the old version — a bug this
# suite caught in the installer, so the fixture must not paper over it.
flip_current() { # $1 build name
  ln -s "$1" "$VERSIONS/.current.tmp"
  python3 -c 'import os, sys; os.replace(sys.argv[1], sys.argv[2])' \
    "$VERSIONS/.current.tmp" "$VERSIONS/current"
}
flip_current "20260804-110000-bbbbbbb"

run_shim session-A builder
case "$OUT" in *"build=old"*) pass "a pinned session is unaffected by a mid-flight repair" ;;
  *) fail "a pinned session is unaffected by a mid-flight repair — got '$OUT'" ;; esac
check "a pinned session keeps its verdict too" 2 "$RC"

run_shim session-B builder
case "$OUT" in *"build=new"*) pass "a session started after the repair gets it" ;;
  *) fail "a session started after the repair gets it — got '$OUT'" ;; esac
check "the new build's verdict applies to the new session" 0 "$RC"

# --- the shim's own content is build-independent: it is the file the harness
# re-reads on every call, so it must be the thing that stops changing.
case "$(cat "$HOOKS/probe-hook.sh")" in
  *aaaaaaa*|*bbbbbbb*) fail "the shim names no build" ;;
  *) pass "the shim names no build" ;;
esac

# --- no session id (a CLI invocation, or a payload without one): the current
# build is the only defensible answer, and nothing is pinned.
set +e
OUT="$(printf '{}' | bash "$HOOKS/probe-hook.sh" verifier 2>/dev/null)"; RC=$?
set -u
case "$OUT" in *"build=new"*) pass "a payload with no session id runs the current build" ;;
  *) fail "a payload with no session id runs the current build — got '$OUT'" ;; esac

# --- fail closed. An unresolvable build must block, never let the call through.
rm -f "$VERSIONS/current"
set +e
printf '%s' "$(payload session-C)" | bash "$HOOKS/probe-hook.sh" builder >/dev/null 2>"$TMP/err"; RC=$?
set -u
check "an unresolvable build blocks" 2 "$RC"
if grep -q "install.sh" "$TMP/err"; then pass "the block says how to repair it"; else fail "the block says how to repair it"; fi

# A pin naming a build that was pruned falls back to current rather than bricking
# the rest of the session.
flip_current "20260804-110000-bbbbbbb"
printf '%s\n' "$VERSIONS/20260804-999999-deleted" > "$AGENT_TEAM_PIN_DIR/session-D"
run_shim session-D builder
case "$OUT" in *"build=new"*) pass "a pin naming a pruned build falls back to current" ;;
  *) fail "a pin naming a pruned build falls back to current — got '$OUT'" ;; esac

# A session id that is not a safe file name cannot escape the pins directory.
run_shim "../escape" builder
if [ -e "$TMP/escape" ] || [ -e "$AGENT_TEAM_PIN_DIR/../escape" ]; then
  fail "a traversal session id cannot write outside the pins dir"
else pass "a traversal session id cannot write outside the pins dir"; fi

# --- --resolve is the single authority both shim flavors use.
check "--resolve prints the pinned build for a known session" \
  "$VERSIONS/20260804-100000-aaaaaaa" \
  "$(bash "$HOOKS/agent-team-pin.sh" --resolve session-A 2>/dev/null)"
check "--resolve prints the current build for an unknown session" \
  "$VERSIONS/20260804-110000-bbbbbbb" \
  "$(bash "$HOOKS/agent-team-pin.sh" --resolve session-NEW 2>/dev/null)"

# --- INSTALL: a real install produces this shape, and installing twice keeps the
# first build on disk so a session pinned to it keeps working.
SANDBOX_HOME="$TMP/home"
PROFILE="$TMP/profile"
mkdir -p "$SANDBOX_HOME" "$PROFILE"
INSTALLED_HOOKS="$SANDBOX_HOME/.claude/hooks"
if AGENT_TEAM_SKIP_INSTALL_TEST=1 HOME="$SANDBOX_HOME" AGENT_TEAM_PIN_DIR="$TMP/pins-install" \
     bash "$REPO/install.sh" --profile "$PROFILE" > "$TMP/install.log" 2>&1; then
  pass "install exits 0"
else
  fail "install exits 0 — $(tail -3 "$TMP/install.log")"
fi
BUILD1="$(cd "$INSTALLED_HOOKS/agent-team-versions/current" 2>/dev/null && pwd -P || true)"
if [ -n "$BUILD1" ] && [ -d "$BUILD1" ]; then pass "install points current at a build"; else fail "install points current at a build"; fi
if [ -f "$BUILD1/agent-team-worktree-guard.sh" ] \
   && [ "$(shasum -a 256 "$BUILD1/agent-team-worktree-guard.sh" | awk '{print $1}')" \
      = "$(shasum -a 256 "$REPO/hooks/agent-team-worktree-guard.sh" | awk '{print $1}')" ]; then
  pass "the build carries the repo's guard verbatim"
else fail "the build carries the repo's guard verbatim"; fi
if grep -q "agent-team hook shim" "$INSTALLED_HOOKS/agent-team-worktree-guard.sh"; then
  pass "the wired bash path is the generated shim"
else fail "the wired bash path is the generated shim"; fi
if grep -q "agent-team hook shim" "$INSTALLED_HOOKS/session_start.py"; then
  pass "the wired python path is the generated shim"
else fail "the wired python path is the generated shim"; fi
# The lint the dispatch guard resolves beside itself has to be inside the build,
# or a pinned guard would fail closed on every builder dispatch.
if [ -f "$BUILD1/lint_acceptance_checks.py" ]; then pass "the build carries the acceptance lint"
else fail "the build carries the acceptance lint"; fi
if AGENT_TEAM_SKIP_INSTALL_TEST=1 HOME="$SANDBOX_HOME" bash "$REPO/install.sh" --check --profile "$PROFILE" \
     > "$TMP/check.log" 2>&1; then
  pass "install --check passes against a pinned install"
else
  fail "install --check passes against a pinned install — $(tail -3 "$TMP/check.log")"
fi
# A hand edit to a wired path un-pins every session on the machine, so --check
# must call it out rather than compare it against the repo and see a match.
printf '#!/usr/bin/env bash\nexit 0\n' > "$INSTALLED_HOOKS/agent-team-lane-guard.sh"
if AGENT_TEAM_SKIP_INSTALL_TEST=1 HOME="$SANDBOX_HOME" bash "$REPO/install.sh" --check --profile "$PROFILE" \
     2>&1 | grep -q "is not the generated shim"; then
  pass "--check catches a hand-edited wired path"
else fail "--check catches a hand-edited wired path"; fi

sleep 1   # build ids carry a second-resolution stamp; a distinct one is the point
if AGENT_TEAM_SKIP_INSTALL_TEST=1 HOME="$SANDBOX_HOME" AGENT_TEAM_PIN_DIR="$TMP/pins-install" \
     bash "$REPO/install.sh" --profile "$PROFILE" >> "$TMP/install.log" 2>&1; then
  pass "a second install exits 0"
else fail "a second install exits 0 — $(tail -3 "$TMP/install.log")"; fi
BUILD2="$(cd "$INSTALLED_HOOKS/agent-team-versions/current" 2>/dev/null && pwd -P || true)"
if [ "$BUILD1" != "$BUILD2" ]; then pass "a second install writes a new build"; else fail "a second install writes a new build"; fi
if [ -d "$BUILD1" ]; then pass "the previous build survives so a pinned session keeps working"
else fail "the previous build survives so a pinned session keeps working"; fi

echo "hook-pin tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
