#!/usr/bin/env bash
# agent-team-audit.sh — the flight recorder (approve-intent spec,
# docs/superpowers/specs/2026-07-12-approve-intent-not-commands-design.md).
# Usage: agent-team-audit.sh ROLE   (PostToolUse hook JSON on stdin)
# Appends "<UTC timestamp> role=<role> ran=<command>" for every Bash call.
# ALWAYS exits 0 — it can never block, prompt, or fail an agent's tool call;
# a logging failure is silently swallowed by design.
set -u

ROLE="${1:-unknown}"
INPUT="$(cat)"
LOG_FILE="${AGENT_TEAM_AUDIT_LOG:-$HOME/.claude/logs/agent-team-audit.log}"

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[ "$TOOL" = "Bash" ] || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$CMD" ] || exit 0

{
  mkdir -p "$(dirname "$LOG_FILE")" && \
  printf '%s role=%s ran=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ROLE" "$CMD" >> "$LOG_FILE"
} 2>/dev/null || true
exit 0
