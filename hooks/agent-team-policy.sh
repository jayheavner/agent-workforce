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
ACTIVE_MODEL="$(printf '%s' "$INPUT" | jq -r '.model // empty')"
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

if [ -n "${AGENT_TEAM_EXPECTED_MODEL:-}" ] \
  && [ "$ACTIVE_MODEL" != "$AGENT_TEAM_EXPECTED_MODEL" ]; then
  block "active model '$ACTIVE_MODEL' does not match pinned profile model '$AGENT_TEAM_EXPECTED_MODEL'" \
    "model-mismatch:$ACTIVE_MODEL"
fi

case "$TOOL" in
  Bash)
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
    check_global_rules
    case "$ROLE" in
      builder) policy_builder ;;
      deployer) policy_deployer ;;
      ops) policy_ops ;;
      verifier|reviewer|debugger) policy_readonly_runner ;;
      architect|researcher|scribe|ticketer)
        block "shell access is not part of the $ROLE role" "$CMD" ;;
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
  apply_patch)
    CONTENT="$(printf '%s' "$INPUT" | jq -r '
      if (.tool_input | type) == "string" then .tool_input
      else (.tool_input.patch // .tool_input.input // empty)
      end
    ')"
    check_write_content_secrets
    if printf '%s\n' "$CONTENT" | grep -q '^\*\*\* Delete File:'; then
      block "file deletion through apply_patch is not allowed for $ROLE" "$CONTENT"
    fi
    case "$ROLE" in
      architect|scribe)
        found=0
        while IFS= read -r FILE; do
          [ -n "$FILE" ] || continue
          found=1
          if has_in "$FILE" '(^|/)\.\.(/|$)'; then
            block "patch path contains a '..' segment" "$FILE"
          fi
          case "$FILE" in
            docs/*|plans/*|doc-inventory/*|scratchpad/*|STATUS.md|STATUS-*.md|*/docs/*|*/plans/*|*/doc-inventory/*|*/scratchpad/*|*/STATUS.md|*/STATUS-*.md) : ;;
            *) block "patch writes are limited to documentation paths for $ROLE" "$FILE" ;;
          esac
        done <<EOF
$(printf '%s\n' "$CONTENT" | sed -nE 's/^\*\*\* (Add|Update) File:[[:space:]]*//p')
EOF
        [ "$found" -eq 1 ] || block "could not identify any patch target path" "$CONTENT"
        allow "$CONTENT"
        ;;
      builder) allow "$CONTENT" ;;
      *) block "file edits are not part of the $ROLE role" "$CONTENT" ;;
    esac
    ;;
  Agent|spawn_agent|collaboration.spawn_agent)
    [ "$ROLE" = "orchestrator" ] \
      || block "specialists may not spawn nested agents" "$TOOL"
    allow "$TOOL"
    ;;
  *)
    allow "tool=$TOOL"
    ;;
esac
