#!/usr/bin/env bash
# agent-team-secrets.sh — the team's single blocking rule (approve-intent spec,
# docs/superpowers/specs/2026-07-12-approve-intent-not-commands-design.md).
# Usage: agent-team-secrets.sh ROLE   (hook JSON on stdin)
# Exit 0 = allow. Exit 2 = block. Blocks two things and nothing else:
#   1. Bash: a credential-bearing variable directed at a file (redirect or tee).
#   2. Write/Edit/NotebookEdit/apply_patch: file content referencing a
#      credential-bearing variable name.
# Ported verbatim from the retired policy lib (same SECRET_RE, same
# /dev/null and fd-dup stripping). Fails open on anything it cannot parse.
set -u

ROLE="${1:-unknown}"
INPUT="$(cat)"
TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
LOG_FILE="${AGENT_TEAM_AUDIT_LOG:-$HOME/.claude/logs/agent-team-audit.log}"

# Codex parity: when a profile pins AGENT_TEAM_EXPECTED_MODEL, a mismatch means
# the wrong runtime is executing this role — identity enforcement, not command
# gating, so it survives the approve-intent redesign.
ACTIVE_MODEL="$(printf '%s' "$INPUT" | jq -r '.model // empty' 2>/dev/null)" || ACTIVE_MODEL=""
if [ -n "${AGENT_TEAM_EXPECTED_MODEL:-}" ] && [ "$ACTIVE_MODEL" != "$AGENT_TEAM_EXPECTED_MODEL" ]; then
  TOOL="${TOOL:-unknown}"
  audit_block() { { mkdir -p "$(dirname "$LOG_FILE")" && printf '%s role=%s tool=%s decision=block detail=%.200s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ROLE" "$TOOL" "$1" >> "$LOG_FILE"; } 2>/dev/null || true; }
  audit_block "model-mismatch:$ACTIVE_MODEL"
  printf 'agent-team secrets guard (%s): active model %s does not match pinned profile model %s\n' "$ROLE" "$ACTIVE_MODEL" "$AGENT_TEAM_EXPECTED_MODEL" >&2
  exit 2
fi

SECRET_RE='\$\{?(OKTA_TOKEN|GODADDY_API_KEY|GODADDY_API_SECRET|OP_SERVICE_ACCOUNT_TOKEN|[A-Za-z_]*_API_KEY|[A-Za-z_]*SECRET[A-Za-z_]*|[A-Za-z_]*PASSWORD[A-Za-z_]*)'

audit_block() { # $1 detail
  { mkdir -p "$(dirname "$LOG_FILE")" && \
    printf '%s role=%s tool=%s decision=block detail=%.200s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ROLE" "$TOOL" "$1" >> "$LOG_FILE"; } 2>/dev/null || true
}

block() { # $1 human reason, $2 detail
  audit_block "$2"
  printf 'agent-team secrets guard (%s): %s\n' "$ROLE" "$1" >&2
  exit 2
}

# Strip harmless /dev/null redirects and fd-to-fd dups (2>&1, 1>&2 …) so the
# file-direction check doesn't false-positive on them; a genuine file redirect
# elsewhere in the same command still matches after stripping.
strip_harmless() {
  printf '%s' "$1" \
    | sed -E 's|[0-9]*>+[[:space:]]*/dev/null||g' \
    | sed -E 's|[0-9]*>&[0-9]+||g'
}

case "$TOOL" in
  Bash)
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
    if printf '%s' "$CMD" | grep -qE "$SECRET_RE"; then
      if strip_harmless "$CMD" | grep -qE '(>>?|\|[[:space:]]*tee([[:space:]]|$))'; then
        block "credential-bearing value directed at a file — forbidden for every role" "$CMD"
      fi
    fi
    ;;
  Write|Edit|NotebookEdit)
    CONTENT="$(printf '%s' "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // .tool_input.new_source // .tool_input.source // empty' 2>/dev/null)" || exit 0
    if [ -n "$CONTENT" ] && printf '%s' "$CONTENT" | grep -qE "$SECRET_RE"; then
      block "file content references a credential-bearing variable name — writing secrets to any file is forbidden for every role" "$CONTENT"
    fi
    ;;
  apply_patch)
    CONTENT="$(printf '%s' "$INPUT" | jq -r '
      if (.tool_input | type) == "string" then .tool_input
      else (.tool_input.patch // .tool_input.input // empty)
      end' 2>/dev/null)" || exit 0
    if [ -n "$CONTENT" ] && printf '%s' "$CONTENT" | grep -qE "$SECRET_RE"; then
      block "patch content references a credential-bearing variable name — writing secrets to any file is forbidden for every role" "$CONTENT"
    fi
    ;;
esac
exit 0
