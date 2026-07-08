#!/usr/bin/env bash
# agent-team-policy.sh — PreToolUse policy for the AI agent team.
# Usage: agent-team-policy.sh ROLE   (hook JSON on stdin)
# Exit 0 = allow. Exit 2 = block (stderr message returned to the agent).
set -u

if [ -z "${1:-}" ]; then
  printf 'agent-team policy: usage: agent-team-policy.sh ROLE\n' >&2
  exit 2
fi
ROLE="$1"
INPUT="$(cat)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')"
CMD=""
FILE=""
CONTENT=""
LOG_FILE="${AGENT_TEAM_AUDIT_LOG:-$HOME/.claude/logs/agent-team-audit.log}"

audit() { # $1 decision, $2 detail
  mkdir -p "$(dirname "$LOG_FILE")"
  printf '%s role=%s tool=%s decision=%s detail=%.200s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ROLE" "$TOOL" "$1" "$2" >> "$LOG_FILE"
}

allow() { audit allow "$1"; exit 0; }

block() { # $1 human reason, $2 detail
  audit block "$2"
  printf 'agent-team policy (%s): %s\n' "$ROLE" "$1" >&2
  exit 2
}

# Shared helpers and per-role policy functions live in agent-team-policy-lib.sh,
# sourced from this script's own directory (not the caller's CWD) so this
# resolves correctly whether invoked by relative path, absolute path, or as
# the install.sh-copied file under ~/.claude/hooks/. Function bodies in the
# sourced file reference $ROLE/$CMD/$LOG_FILE etc., but only when CALLED, not
# at source time — this file has no top-level code — so sourcing after the
# variable setup above is safe and reads naturally top-to-bottom.
source "$(cd "$(dirname "$0")" && pwd)/agent-team-policy-lib.sh"

case "$TOOL" in
  Bash)
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
    check_global_rules
    case "$ROLE" in
      builder) policy_builder ;;
      deployer) policy_deployer ;;
      ops) policy_ops ;;
      verifier|reviewer) policy_readonly_runner ;;
      *) allow "$CMD" ;;
    esac
    ;;
  Write|Edit|NotebookEdit)
    FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
    CONTENT="$(printf '%s' "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // .tool_input.new_source // .tool_input.source // empty')"
    check_write_content_secrets
    case "$ROLE" in
      architect|scribe) policy_docwriter_path ;;
      *) allow "$FILE" ;;
    esac
    ;;
  *)
    allow "tool=$TOOL"
    ;;
esac
