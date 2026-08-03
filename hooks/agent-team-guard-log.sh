#!/usr/bin/env bash
# agent-team-guard-log.sh — shared block recorder for the workforce guards.
#
# Sourced, not executed: a guard sources this file and calls
#   guard_log <guard-name> <role> <verdict> <detail>
# immediately before it exits 2 (or before a deliberate fail-open).
#
# Why this exists: a refusal that only reaches the agent's stderr is invisible.
# "The executor was refused a source write four times this week" is the leading
# indicator that routing is probing for a way around a control, and until this
# hook there was nowhere that fact could accumulate. Fail-opens matter even more
# — a control that quietly stopped enforcing looks exactly like a control that
# was never needed.
#
# Writes JSON lines to workforce-owned storage, NEVER into the repository being
# worked on: a hook must not create dirt that other hooks then police. Every
# failure path is silent and non-fatal — telemetry must never turn a guard
# decision into a crash.

guard_log() { # $1 guard $2 role $3 verdict (block|fail-open) $4 detail
  local dir file stamp
  dir="${AGENT_TEAM_TELEMETRY_DIR:-$HOME/.claude/logs/agent-team-telemetry}"
  mkdir -p "$dir" 2>/dev/null || return 0
  file="$dir/guard-blocks.jsonl"
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || stamp=""
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$stamp" --arg g "${1:-}" --arg r "${2:-}" \
           --arg v "${3:-}" --arg d "${4:-}" \
      '{ts:$ts,guard:$g,role:$r,verdict:$v,detail:$d}' >> "$file" 2>/dev/null
  else
    # jq absent is exactly when a guard fails closed, so the record still matters.
    printf '{"ts":"%s","guard":"%s","role":"%s","verdict":"%s","detail":"jq unavailable"}\n' \
      "$stamp" "${1:-}" "${2:-}" "${3:-}" >> "$file" 2>/dev/null
  fi
  return 0
}
