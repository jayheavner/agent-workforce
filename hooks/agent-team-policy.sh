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

has() { printf '%s' "$CMD" | grep -qE "$1"; }

policy_builder() {
  if has '(^|[;&|[:space:]])(aws|az|gcloud)[[:space:]]'; then
    block "builder has no cloud CLI access — hand cloud work to ops or deployer" "$CMD"
  fi
  if has '(^|[;&|[:space:]])(amplify|cdk|terraform)([[:space:]]|$)'; then
    block "deploy toolchain belongs to the deployer" "$CMD"
  fi
  if has '(^|[;&|[:space:]])sam[[:space:]]+deploy'; then
    block "sam deploy belongs to the deployer" "$CMD"
  fi
  if has 'git[[:space:]]+push'; then
    if has 'git[[:space:]]+push[^;&|]*[[:space:]](main|master)([[:space:]]|$|:)'; then
      block "builder may not push to main/master" "$CMD"
    fi
    if ! has 'git[[:space:]]+push[[:space:]]+(-u[[:space:]]+)?[^-[:space:]][^[:space:]]*[[:space:]]+[^[:space:]]+'; then
      block "git push must name a remote and an explicit feature branch" "$CMD"
    fi
  fi
  allow "$CMD"
}

# stdin command with harmless /dev/null redirections removed,
# so redirection checks don't false-positive on "2>/dev/null".
stripped_cmd() { printf '%s' "$CMD" | sed -E 's|[0-9]*>+[[:space:]]*/dev/null||g'; }

SECRET_RE='\$\{?(OKTA_TOKEN|GODADDY_API_KEY|GODADDY_API_SECRET|OP_SERVICE_ACCOUNT_TOKEN|[A-Za-z_]*_API_KEY|[A-Za-z_]*SECRET[A-Za-z_]*|[A-Za-z_]*PASSWORD[A-Za-z_]*)'

check_global_rules() {
  if has "$SECRET_RE"; then
    if printf '%s' "$(stripped_cmd)" | grep -qE '(>>?|\|[[:space:]]*tee([[:space:]]|$))'; then
      block "credential-bearing value directed at a file — forbidden for every role" "$CMD"
    fi
  fi
  case "$ROLE" in
    ops|deployer) : ;;
    *)
      if has '(^|[;&|[:space:]])op[[:space:]]'; then
        block "only ops and deployer may invoke the 1Password CLI" "$CMD"
      fi
      ;;
  esac
  return 0
}

case "$TOOL" in
  Bash)
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')"
    check_global_rules
    case "$ROLE" in
      builder) policy_builder ;;
      *) allow "$CMD" ;;
    esac
    ;;
  Write|Edit|NotebookEdit)
    FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
    case "$ROLE" in
      *) allow "$FILE" ;;
    esac
    ;;
  *)
    allow "tool=$TOOL"
    ;;
esac
