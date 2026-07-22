#!/usr/bin/env bash
# Route plugin-level hooks to the existing role-aware hook implementations.
# Claude Code ignores hooks embedded in plugin agent definitions, while plugin
# hooks apply to the whole session. This adapter restores per-role behavior and
# deliberately ignores agents that are not part of this workforce.
set -u

MODE="${1:-}"
case "$MODE" in
  secrets|audit|dispatch|cost|closeout-stop|archive-run|session-start) ;;
  *)
    printf 'agent-workforce plugin router: unknown routing mode: %s\n' "$MODE" >&2
    exit 2
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  printf 'agent-workforce plugin router: jq is required to identify the active agent safely\n' >&2
  exit 2
fi

INPUT="$(cat)"
HERE="$(cd "$(dirname "$0")" && pwd)"

# Stop does not reliably carry agent_type. The closeout hook self-scopes: it
# enforces only in sessions that actually dispatched workforce specialists.
if [ "$MODE" = "closeout-stop" ]; then
  printf '%s' "$INPUT" | python3 "$HERE/agent_team_closeout.py"
  exit $?
fi

# Transcript archiver self-scopes by event (Stop vs SessionEnd) and is
# always fail-open — it must never block a stop or an exit.
if [ "$MODE" = "archive-run" ]; then
  printf '%s' "$INPUT" | python3 "$HERE/debug_run_archiver.py"
  exit 0
fi

# SessionStart grounding (git sync + onboarding probe) carries no agent_type
# in its payload and is informational context only — always fail-open.
if [ "$MODE" = "session-start" ]; then
  printf '%s' "$INPUT" | python3 "$HERE/session_start.py"
  exit 0
fi

ROLE="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)" || {
  printf 'agent-workforce plugin router: hook input was not valid JSON\n' >&2
  exit 2
}

# Installed plugin agents may be reported either as their bare name or with
# this plugin's namespace. Do not normalize another plugin's role name into a
# workforce role: plugin hooks are session-global and must not leak.
case "$ROLE" in
  agent-workforce:*) ROLE="${ROLE#agent-workforce:}" ;;
  *:*) exit 0 ;;
esac

case "$ROLE" in
  orchestrator|architect|builder|debugger|verifier|reviewer|deployer|executor|researcher|ops|scribe|ticketer) ;;
  *) exit 0 ;;
esac

case "$MODE" in
  secrets)
    printf '%s' "$INPUT" | bash "$HERE/agent-team-secrets.sh" "$ROLE"
    ;;
  audit)
    printf '%s' "$INPUT" | bash "$HERE/agent-team-audit.sh" "$ROLE"
    ;;
  dispatch)
    [ "$ROLE" = "orchestrator" ] || exit 0
    printf '%s' "$INPUT" | bash "$HERE/agent-team-dispatch-guard.sh"
    ;;
  cost)
    [ "$ROLE" = "orchestrator" ] || exit 0
    printf '%s' "$INPUT" | bash "$HERE/agent-team-cost.sh"
    ;;
esac
