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
has_in() { printf '%s' "$1" | grep -qE "$2"; } # $1 string, $2 pattern

# Splits $CMD on shell control operators (&&, ||, ;, |) and feeds each
# trimmed, non-empty segment to callback $1, one call per segment.
# Uses `< <(...)` process substitution (not a trailing pipe) so the while
# loop runs in THIS shell process, not a subshell — verified under macOS
# bash 3.2: `cmd | while read ...; do exit 2; done` only exits the
# subshell and lets the script continue, silently defeating blocking.
# `while read ...; done < <(cmd)` propagates exit 2 to the real process.
each_segment() { # $1 = callback name, invoked once per chain segment of $CMD
  local cb="$1" seg
  while IFS= read -r seg; do
    seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$seg" ] && "$cb" "$seg"
  done < <(printf '%s\n' "$CMD" | sed -E 's/(&&|\|\||;|\|)/\n/g')
}

_deny_shell_mutation_seg() { # $1 = one chain segment
  local seg="$1"
  if has_in "$seg" '(^|[;&|[:space:]])(rm|mv|cp|mkdir|touch|chmod|chown|ln|dd|truncate)[[:space:]]'; then
    block "file-mutating command not allowed for $ROLE" "$CMD"
  fi
  if has_in "$(stripped_cmd_of "$seg")" '>>?'; then
    block "output redirection to a file not allowed for $ROLE" "$CMD"
  fi
  if has_in "$seg" '\|[[:space:]]*tee([[:space:]]|$)'; then
    block "tee not allowed for $ROLE" "$CMD"
  fi
  if has_in "$seg" 'sed[[:space:]]+(-[A-Za-z]*i|--in-place)'; then
    block "in-place edit not allowed for $ROLE" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])git[[:space:]]+(add|commit|push|reset|checkout|restore|clean|rebase|merge|stash|tag|rm)([[:space:]]|$)'; then
    block "mutating git command not allowed for $ROLE" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])(npm|pnpm|yarn|pip3?|uv|brew)[[:space:]]+(install|add|uninstall|remove|upgrade)'; then
    block "package management not allowed for $ROLE" "$CMD"
  fi
  return 0
}

# Chain-aware: every segment is checked independently, so a mutation
# hidden after a benign/whitelisted segment (e.g. `sam deploy && rm -rf /`)
# is still caught.
deny_shell_mutation() {
  each_segment _deny_shell_mutation_seg
  return 0
}

_policy_deployer_seg() { # $1 = one chain segment; blocks on any disallowed segment
  local seg="$1"
  if has_in "$seg" '(^|[;&|[:space:]])(sam|amplify|cdk)([[:space:]]|$)'; then
    return 0
  fi
  if has_in "$seg" '(^|[;&|[:space:]])aws[[:space:]]'; then
    if has_in "$seg" 'aws[[:space:]]+cloudformation[[:space:]]' \
      || has_in "$seg" 'aws[[:space:]]+s3[[:space:]]+(sync|cp|ls)([[:space:]]|$)' \
      || has_in "$seg" 'aws[[:space:]]+sts[[:space:]]' \
      || has_in "$seg" 'aws[[:space:]]+[a-z0-9-]+[[:space:]]+(get-|list-|describe-|head-)'; then
      return 0
    fi
    block "aws command outside the deploy toolchain — surface it to the human at a gate" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])terraform([[:space:]]|$)'; then
    block "terraform is not part of this team's deploy toolchain" "$CMD"
  fi
  _deny_shell_mutation_seg "$seg"
}

# Every segment of the chain must independently be a recognized-safe
# deploy-toolchain/aws-allowlisted call, or pass the mutation checks with
# no block. Only after ALL segments clear does the whole command allow —
# matching one segment against sam/amplify/cdk/aws no longer short-circuits
# an allow for the rest of the chain (that was the bypass).
policy_deployer() {
  each_segment _policy_deployer_seg
  allow "$CMD"
}

policy_readonly_runner() {
  if has '(^|[;&|[:space:]])(aws|az|gcloud)[[:space:]]'; then
    block "no cloud CLI for $ROLE" "$CMD"
  fi
  if has '(^|[;&|[:space:]])(sam|amplify|cdk|terraform)([[:space:]]|$)'; then
    block "deploy toolchain is reserved for the deployer" "$CMD"
  fi
  deny_shell_mutation
  allow "$CMD"
}

_policy_builder_seg() { # $1 = one chain segment
  local seg="$1"
  if has_in "$seg" '(^|[;&|[:space:]])(aws|az|gcloud)[[:space:]]'; then
    block "builder has no cloud CLI access — hand cloud work to ops or deployer" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])(amplify|cdk|terraform)([[:space:]]|$)'; then
    block "deploy toolchain belongs to the deployer" "$CMD"
  fi
  if has_in "$seg" '(^|[;&|[:space:]])sam[[:space:]]+deploy([[:space:]]|$)'; then
    block "sam deploy belongs to the deployer" "$CMD"
  fi
  if has_in "$seg" 'git[[:space:]]+push'; then
    # Three independent checks catch main/master as: a bare whitespace-delimited
    # token, the destination side of a ':'-separated refspec (e.g. HEAD:main),
    # or a fully-qualified refs/heads/ path — without false-positiving on a
    # feature-prefixed branch that merely contains "main" as a path segment
    # (e.g. feature/main). Segment is already chain-isolated so no [;&|] can
    # appear inside it, but the patterns are kept as-is (harmless) for parity
    # with the pre-chaining-fix behavior.
    if has_in "$seg" 'git[[:space:]]+push[^;&|]*[[:space:]](main|master)([[:space:]]|$|:)'; then
      block "builder may not push to main/master" "$CMD"
    fi
    if has_in "$seg" ':(main|master)([[:space:]]|$)'; then
      block "builder may not push to main/master" "$CMD"
    fi
    if has_in "$seg" '(^|[;&|[:space:]:])refs/heads/(main|master)([[:space:]]|$|:)'; then
      block "builder may not push to main/master" "$CMD"
    fi
    if ! has_in "$seg" 'git[[:space:]]+push[[:space:]]+(-u[[:space:]]+)?[^-[:space:]][^[:space:]]*[[:space:]]+[^[:space:]]+'; then
      block "git push must name a remote and an explicit feature branch" "$CMD"
    fi
  fi
  return 0
}

# NOTE: policy_builder intentionally does NOT call deny_shell_mutation,
# matching its pre-existing (Task 3) behavior — see task-5-report.md for
# why this is flagged to the human rather than silently changed here.
policy_builder() {
  each_segment _policy_builder_seg
  allow "$CMD"
}

# stdin command (or an arbitrary string, via stripped_cmd_of) with harmless
# /dev/null redirections removed, so redirection checks don't
# false-positive on "2>/dev/null".
stripped_cmd() { stripped_cmd_of "$CMD"; }
stripped_cmd_of() { printf '%s' "$1" | sed -E 's|[0-9]*>+[[:space:]]*/dev/null||g'; }

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
      deployer) policy_deployer ;;
      verifier|reviewer) policy_readonly_runner ;;
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
