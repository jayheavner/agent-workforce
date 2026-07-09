#!/usr/bin/env bash
# install.sh — validate, back up, install the agent team into ~/.claude/.
# install.sh --check — verify the installed team against the last install's
# manifest and against the repo, without touching anything: detects hand-edits
# under ~/.claude/, a repo that moved on without a reinstall, and machine-level
# rot (missing skills, missing jq). Exits nonzero on any drift.
set -u

REPO="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CLAUDE_DIR/backups/agent-team-$STAMP"
MANIFEST="$CLAUDE_DIR/agent-team-manifest.json"
MODE="install"
[ "${1:-}" = "--check" ] && MODE="check"

fail() { echo "$MODE: FAIL — $*" >&2; exit 1; }
warn() { echo "$MODE: WARNING — $*" >&2; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
HOOK_FILES="agent-team-policy.sh agent-team-policy-lib.sh agent-team-policy-mutations.sh agent-team-cost.sh agent-team-dispatch-guard.sh model-rates.json"

# --- validation (nothing is touched until all of this passes) ---
command -v jq >/dev/null 2>&1 || fail "jq is required"
[ -f "$REPO/hooks/agent-team-policy-lib.sh" ] || fail "hooks/agent-team-policy-lib.sh is missing from repo"
[ -f "$REPO/hooks/agent-team-policy-mutations.sh" ] || fail "hooks/agent-team-policy-mutations.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-policy.sh" || fail "policy script failed bash -n"
bash -n "$REPO/hooks/agent-team-policy-lib.sh" || fail "policy lib script failed bash -n"
bash -n "$REPO/hooks/agent-team-policy-mutations.sh" || fail "policy mutations script failed bash -n"
[ -f "$REPO/hooks/agent-team-cost.sh" ] || fail "hooks/agent-team-cost.sh is missing from repo"
[ -f "$REPO/hooks/model-rates.json" ] || fail "hooks/model-rates.json is missing from repo"
bash -n "$REPO/hooks/agent-team-cost.sh" || fail "cost hook failed bash -n"
[ -f "$REPO/hooks/agent-team-dispatch-guard.sh" ] || fail "hooks/agent-team-dispatch-guard.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-dispatch-guard.sh" || fail "dispatch guard failed bash -n"
jq empty "$REPO/hooks/model-rates.json" || fail "model-rates.json is not valid JSON"
jq -e '
  def rates: [ .input, .output, .cache_write_5m, .cache_write_1h, .cache_read ];
  def entries: [ .models[], ( .models[].intro | select(. != null) ) ];
  ([ entries[] | rates[] | type == "number" ] | all)
  and
  # No rate may carry more than 4 fractional decimal digits: r*10000 must be an
  # integer. Protects the hook nofloat 10-decimal snap invariant.
  ([ entries[] | rates[] | (. * 10000) | (. == (. | floor)) ] | all)
' "$REPO/hooks/model-rates.json" >/dev/null \
  || fail "model-rates.json: every model needs five numeric rate keys, each with at most 4 fractional decimal digits"
bash "$REPO/tests/test_policy_hooks.sh" >/dev/null || fail "policy hook tests failed — run tests/test_policy_hooks.sh to see which"
bash "$REPO/tests/test_cost_hook.sh" >/dev/null || fail "cost hook tests failed — run tests/test_cost_hook.sh to see which"
bash "$REPO/tests/test_dispatch_guard.sh" >/dev/null || fail "dispatch guard tests failed — run tests/test_dispatch_guard.sh to see which"

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

# Skills the architect invokes situationally via the Skill tool rather than
# preloading in its skills: frontmatter — invisible to the loop above, but a
# missing one still breaks the architect at runtime, so the same loud-failure
# rule applies at install time.
for s in superpowers:brainstorming plan-review ux-to-ui-design; do
  resolve_skill "$s" || fail "architect situational skill '$s' does not resolve to an installed skill"
done

[ -n "${CLAUDE_CODE_SUBAGENT_MODEL:-}" ] \
  && warn "CLAUDE_CODE_SUBAGENT_MODEL is set in this environment; it overrides every model pin"
for rc in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv"; do
  [ -f "$rc" ] && grep -q 'CLAUDE_CODE_SUBAGENT_MODEL' "$rc" \
    && warn "CLAUDE_CODE_SUBAGENT_MODEL appears in $rc; it overrides every model pin"
done

# --- check mode: compare manifest vs installed vs repo, then stop ---
if [ "$MODE" = "check" ]; then
  [ -f "$MANIFEST" ] || fail "no manifest at $MANIFEST — run 'bash install.sh' once first"
  jq empty "$MANIFEST" 2>/dev/null || fail "manifest at $MANIFEST is not valid JSON — re-run 'bash install.sh'"
  drift=0
  while IFS="$(printf '\t')" read -r rel recorded; do
    [ -n "$rel" ] || continue
    case "$rel" in
      agents/*) inst="$CLAUDE_DIR/agents/$(basename "$rel")" ;;
      hooks/*)  inst="$CLAUDE_DIR/hooks/$(basename "$rel")" ;;
      *) continue ;;
    esac
    if [ ! -f "$inst" ]; then
      echo "check: MISSING — $inst was installed but is gone"; drift=1
    elif [ "$(sha "$inst")" != "$recorded" ]; then
      echo "check: DRIFT — $inst differs from the last install (hand-edited under ~/.claude/?)"; drift=1
    fi
    if [ ! -f "$REPO/$rel" ]; then
      echo "check: REMOVED — $rel is gone from the repo; re-run install to retire it cleanly"; drift=1
    elif [ "$(sha "$REPO/$rel")" != "$recorded" ]; then
      echo "check: STALE — repo $rel changed since the last install; re-run install"; drift=1
    fi
  done <<EOF
$(jq -r '.files | to_entries[] | "\(.key)\t\(.value)"' "$MANIFEST")
EOF
  for f in "$REPO"/agents/*.md; do
    rel="agents/$(basename "$f")"
    jq -e --arg k "$rel" '.files[$k] != null' "$MANIFEST" >/dev/null \
      || { echo "check: NEW — $rel exists in the repo but was never installed"; drift=1; }
  done
  if [ "$drift" -eq 0 ]; then
    echo "check: OK — installed team matches repo build $(jq -r '.commit' "$MANIFEST") (installed $(jq -r '.installed_at' "$MANIFEST"))"
    exit 0
  fi
  fail "drift detected (lines above). Reconcile any hand edits back into the repo, then re-run 'bash install.sh'"
fi

# --- backup ---
mkdir -p "$BACKUP" "$CLAUDE_DIR/agents" "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/logs" || fail "cannot create target directories"

# Track which of the files this installer manages were pre-existing (i.e. got
# a backup copy) vs. not, so a failure partway through install can tell "roll
# back to the old version" apart from "this was never here — remove it."
PREEXISTING_AGENTS=""
for f in "$REPO"/agents/*.md; do
  bn="$(basename "$f")"
  existing="$CLAUDE_DIR/agents/$bn"
  if [ -f "$existing" ]; then
    cp "$existing" "$BACKUP/"
    PREEXISTING_AGENTS="$PREEXISTING_AGENTS $bn"
  fi
done
PREEXISTING_POLICY=0
PREEXISTING_POLICY_LIB=0
PREEXISTING_POLICY_MUT=0
[ -f "$CLAUDE_DIR/hooks/agent-team-policy.sh" ] && { cp "$CLAUDE_DIR/hooks/agent-team-policy.sh" "$BACKUP/"; PREEXISTING_POLICY=1; }
[ -f "$CLAUDE_DIR/hooks/agent-team-policy-lib.sh" ] && { cp "$CLAUDE_DIR/hooks/agent-team-policy-lib.sh" "$BACKUP/"; PREEXISTING_POLICY_LIB=1; }
[ -f "$CLAUDE_DIR/hooks/agent-team-policy-mutations.sh" ] && { cp "$CLAUDE_DIR/hooks/agent-team-policy-mutations.sh" "$BACKUP/"; PREEXISTING_POLICY_MUT=1; }
PREEXISTING_COST=0
PREEXISTING_RATES=0
PREEXISTING_GUARD=0
[ -f "$CLAUDE_DIR/hooks/agent-team-cost.sh" ] && { cp "$CLAUDE_DIR/hooks/agent-team-cost.sh" "$BACKUP/"; PREEXISTING_COST=1; }
[ -f "$CLAUDE_DIR/hooks/model-rates.json" ] && { cp "$CLAUDE_DIR/hooks/model-rates.json" "$BACKUP/"; PREEXISTING_RATES=1; }
[ -f "$CLAUDE_DIR/hooks/agent-team-dispatch-guard.sh" ] && { cp "$CLAUDE_DIR/hooks/agent-team-dispatch-guard.sh" "$BACKUP/"; PREEXISTING_GUARD=1; }

restore() {
  echo "install: restoring backup from $BACKUP" >&2
  for b in "$BACKUP"/*; do
    [ -f "$b" ] || continue
    case "$(basename "$b")" in
      agent-team-policy.sh) cp "$b" "$CLAUDE_DIR/hooks/" ;;
      agent-team-policy-lib.sh) cp "$b" "$CLAUDE_DIR/hooks/" ;;
      agent-team-policy-mutations.sh) cp "$b" "$CLAUDE_DIR/hooks/" ;;
      agent-team-cost.sh) cp "$b" "$CLAUDE_DIR/hooks/" ;;
      agent-team-dispatch-guard.sh) cp "$b" "$CLAUDE_DIR/hooks/" ;;
      model-rates.json) cp "$b" "$CLAUDE_DIR/hooks/" ;;
      *.md) cp "$b" "$CLAUDE_DIR/agents/" ;;
    esac
  done
}

# Undo whatever THIS run freshly installed with no pre-existing version to
# roll back to, so a failed fresh install reverts to "nothing installed"
# instead of leaving a partial (and potentially broken) install behind.
# Only ever touches the exact files this installer manages — never anything
# else that happens to live in $CLAUDE_DIR/agents or $CLAUDE_DIR/hooks.
cleanup_fresh() {
  for f in "$REPO"/agents/*.md; do
    bn="$(basename "$f")"
    case " $PREEXISTING_AGENTS " in
      *" $bn "*) : ;; # was pre-existing; restore() already handled it
      *) rm -f "$CLAUDE_DIR/agents/$bn" ;;
    esac
  done
  [ "$PREEXISTING_POLICY" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/agent-team-policy.sh"
  [ "$PREEXISTING_POLICY_LIB" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/agent-team-policy-lib.sh"
  [ "$PREEXISTING_POLICY_MUT" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/agent-team-policy-mutations.sh"
  [ "$PREEXISTING_COST" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/agent-team-cost.sh"
  [ "$PREEXISTING_RATES" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/model-rates.json"
  [ "$PREEXISTING_GUARD" -eq 0 ] && rm -f "$CLAUDE_DIR/hooks/agent-team-dispatch-guard.sh"
}

# --- install ---
if ! cp "$REPO"/agents/*.md "$CLAUDE_DIR/agents/"; then restore; cleanup_fresh; fail "agent copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-policy.sh" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "hook copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-policy-lib.sh" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "hook lib copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-policy-mutations.sh" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "hook mutations copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-cost.sh" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "cost hook copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-dispatch-guard.sh" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "dispatch guard copy failed; rolled back"; fi
if ! cp "$REPO/hooks/model-rates.json" "$CLAUDE_DIR/hooks/"; then restore; cleanup_fresh; fail "rates file copy failed; rolled back"; fi
# Only the entry point is ever executed directly (agent frontmatter and the
# shell invoke it by path); agent-team-policy-lib.sh and
# agent-team-policy-mutations.sh are only ever `source`d (a two-level chain:
# entry point -> lib -> mutations), so they need to be readable, not executable.
chmod +x "$CLAUDE_DIR/hooks/agent-team-policy.sh" || { restore; cleanup_fresh; fail "chmod failed; rolled back"; }
chmod +x "$CLAUDE_DIR/hooks/agent-team-cost.sh" || { restore; cleanup_fresh; fail "chmod of cost hook failed; rolled back"; }
chmod +x "$CLAUDE_DIR/hooks/agent-team-dispatch-guard.sh" || { restore; cleanup_fresh; fail "chmod of dispatch guard failed; rolled back"; }

# --- manifest: record what this install shipped, so --check can detect drift
# and the orchestrator can announce its build at session start. Metadata only;
# a manifest failure does not undo an already-successful install.
COMMIT="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
TMP_MANIFEST="$(mktemp)"
{
  for f in "$REPO"/agents/*.md; do printf 'agents/%s\t%s\n' "$(basename "$f")" "$(sha "$f")"; done
  for h in $HOOK_FILES; do printf 'hooks/%s\t%s\n' "$h" "$(sha "$REPO/hooks/$h")"; done
} | jq -R -n \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg repo "$REPO" \
    --arg commit "$COMMIT" \
    '{installed_at: $at, repo: $repo, commit: $commit,
      files: ([inputs | select(length > 0) | split("\t") | {(.[0]): .[1]}] | add)}' \
  > "$TMP_MANIFEST"
if jq empty "$TMP_MANIFEST" 2>/dev/null && cp "$TMP_MANIFEST" "$MANIFEST"; then
  rm -f "$TMP_MANIFEST"
else
  rm -f "$TMP_MANIFEST"
  warn "manifest write failed — install is fine, but 'install.sh --check' and the orchestrator's build line won't work until a successful re-install"
fi

echo "install: OK — 10 agents installed, policy hook + cost hook installed, build $COMMIT recorded, backup at $BACKUP"
echo "install: verify any time with: bash install.sh --check"
echo "install: start the team with: claude --agent orchestrator"
