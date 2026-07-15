#!/usr/bin/env bash
# tests/test_install_retire.sh — sandbox install over a stale policy hook
# (approve-intent spec, install retire-and-purge): retired files purged, new
# hooks installed executable, --check OK, then --check fails RETIRED when a
# stale file reappears.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
mkdir -p "$HOME/.claude/hooks"
export AGENT_TEAM_SKIP_INSTALL_TEST=1
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); }
no() { FAIL=$((FAIL+1)); echo "FAIL [$1]"; }

# Plant a stale policy hook from the pre-redesign world.
printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/.claude/hooks/agent-team-policy.sh"

if bash "$REPO/install.sh" --profile "$HOME/.claude" >/dev/null 2>&1; then ok; else no "sandbox install succeeds"; fi

for h in agent-team-policy.sh agent-team-policy-lib.sh agent-team-policy-mutations.sh; do
  [ ! -f "$HOME/.claude/hooks/$h" ] && ok || no "retired $h purged from hooks dir"
done
for h in agent-team-secrets.sh agent-team-audit.sh; do
  [ -x "$HOME/.claude/hooks/$h" ] && ok || no "new hook $h installed executable"
done

bash "$REPO/install.sh" --check --profile "$HOME/.claude" >/dev/null 2>&1 && ok || no "--check OK after retire install"

# A stale policy file reappearing is drift: --check must fail with RETIRED.
printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/.claude/hooks/agent-team-policy.sh"
set +e
OUT="$(bash "$REPO/install.sh" --check --profile "$HOME/.claude" 2>&1)"; RC=$?
set -u
[ "$RC" -ne 0 ] && ok || no "--check fails when a retired hook reappears"
printf '%s' "$OUT" | grep -q "RETIRED" && ok || no "--check names the RETIRED finding"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
