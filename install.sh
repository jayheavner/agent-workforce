#!/usr/bin/env bash
# install.sh — validate, back up, install the agent team into ~/.claude/.
set -u

REPO="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CLAUDE_DIR/backups/agent-team-$STAMP"

fail() { echo "install: FAIL — $*" >&2; exit 1; }
warn() { echo "install: WARNING — $*" >&2; }

# --- validation (nothing is touched until all of this passes) ---
command -v jq >/dev/null 2>&1 || fail "jq is required"
[ -f "$REPO/hooks/agent-team-policy-lib.sh" ] || fail "hooks/agent-team-policy-lib.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-policy.sh" || fail "policy script failed bash -n"
bash -n "$REPO/hooks/agent-team-policy-lib.sh" || fail "policy lib script failed bash -n"
bash "$REPO/tests/test_policy_hooks.sh" >/dev/null || fail "policy hook tests failed — run tests/test_policy_hooks.sh to see which"

# Built-in skills ship with the Claude Code client itself and have no
# SKILL.md on disk anywhere (not under ~/.claude/skills/, not in the plugin
# cache) — "verify" is one of these. Listed explicitly so the check below
# stays a real resolution check rather than a rubber stamp.
BUILTIN_SKILLS=" verify run init review security-review update-config keybindings-help "

resolve_skill() { # $1 skill ref (bare or ns:name) -> 0 if found
  case "$1" in
    *:*)
      ns="${1%%:*}"; sk="${1#*:}"
      ls "$HOME/.claude/plugins/cache/"*/"$ns"/*/skills/"$sk"/SKILL.md >/dev/null 2>&1
      ;;
    *)
      case "$BUILTIN_SKILLS" in
        *" $1 "*) return 0 ;;
      esac
      [ -f "$HOME/.claude/skills/$1/SKILL.md" ]
      ;;
  esac
}

for f in "$REPO"/agents/*.md; do
  head -1 "$f" | grep -q '^---$' || fail "$f: no frontmatter"
  fm="$(awk '/^---$/{n++; next} n==1{print}' "$f")"
  for key in name description model; do
    printf '%s\n' "$fm" | grep -qE "^$key:" || fail "$f: missing frontmatter key '$key'"
  done
  model="$(printf '%s\n' "$fm" | sed -n 's/^model:[[:space:]]*//p')"
  case "$model" in
    claude-fable-5|claude-opus-4-8|claude-sonnet-5) : ;;
    *) fail "$f: model '$model' is not one of the pinned team models" ;;
  esac
  skills_csv="$(printf '%s\n' "$fm" | sed -n 's/^skills:[[:space:]]*//p')"
  if [ -n "$skills_csv" ]; then
    old_ifs="$IFS"; IFS=','
    for s in $skills_csv; do
      s="$(printf '%s' "$s" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      resolve_skill "$s" || fail "$f: skills entry '$s' does not resolve to an installed skill"
    done
    IFS="$old_ifs"
  fi
done

[ -n "${CLAUDE_CODE_SUBAGENT_MODEL:-}" ] \
  && warn "CLAUDE_CODE_SUBAGENT_MODEL is set in this environment; it overrides every model pin"
for rc in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv"; do
  [ -f "$rc" ] && grep -q 'CLAUDE_CODE_SUBAGENT_MODEL' "$rc" \
    && warn "CLAUDE_CODE_SUBAGENT_MODEL appears in $rc; it overrides every model pin"
done

# --- backup ---
mkdir -p "$BACKUP" "$CLAUDE_DIR/agents" "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/logs" || fail "cannot create target directories"
for f in "$REPO"/agents/*.md; do
  existing="$CLAUDE_DIR/agents/$(basename "$f")"
  [ -f "$existing" ] && cp "$existing" "$BACKUP/"
done
[ -f "$CLAUDE_DIR/hooks/agent-team-policy.sh" ] && cp "$CLAUDE_DIR/hooks/agent-team-policy.sh" "$BACKUP/"
[ -f "$CLAUDE_DIR/hooks/agent-team-policy-lib.sh" ] && cp "$CLAUDE_DIR/hooks/agent-team-policy-lib.sh" "$BACKUP/"

restore() {
  echo "install: restoring backup from $BACKUP" >&2
  for b in "$BACKUP"/*; do
    [ -f "$b" ] || continue
    case "$(basename "$b")" in
      agent-team-policy.sh) cp "$b" "$CLAUDE_DIR/hooks/" ;;
      agent-team-policy-lib.sh) cp "$b" "$CLAUDE_DIR/hooks/" ;;
      *.md) cp "$b" "$CLAUDE_DIR/agents/" ;;
    esac
  done
}

# --- install ---
if ! cp "$REPO"/agents/*.md "$CLAUDE_DIR/agents/"; then restore; fail "agent copy failed; backup restored"; fi
if ! cp "$REPO/hooks/agent-team-policy.sh" "$CLAUDE_DIR/hooks/"; then restore; fail "hook copy failed; backup restored"; fi
if ! cp "$REPO/hooks/agent-team-policy-lib.sh" "$CLAUDE_DIR/hooks/"; then restore; fail "hook lib copy failed; backup restored"; fi
# Only the entry point is ever executed directly (agent frontmatter and the
# shell invoke it by path); agent-team-policy-lib.sh is only ever `source`d
# by agent-team-policy.sh, so it needs to be readable, not executable.
chmod +x "$CLAUDE_DIR/hooks/agent-team-policy.sh" || { restore; fail "chmod failed; backup restored"; }

echo "install: OK — 10 agents installed, policy hook installed, backup at $BACKUP"
echo "install: start the team with: claude --agent orchestrator"
