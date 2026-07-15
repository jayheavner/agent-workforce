#!/usr/bin/env bash
# install.sh — validate, back up, and install the agent team into one Claude
# profile. Use --list-profiles before installation when a machine may have more
# than one profile; use --profile DIR to select one explicitly.
# install.sh --check [--profile DIR] verifies that profile against the last
# install's manifest and the repo without touching anything.
set -u

REPO="$(cd "$(dirname "$0")" && pwd)"
MODE="install"
PROFILE_ARG=""
LIST_PROFILES=0

usage() {
  cat <<'EOF'
Usage:
  bash install.sh [--profile DIR]
  bash install.sh --check [--profile DIR]
  bash install.sh --list-profiles

An explicit --profile takes precedence over CLAUDE_CONFIG_DIR. When neither is
set, the installer discovers profile-shaped $HOME/.claude* directories and
refuses an ambiguous multi-profile install.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --profile)
      [ "$#" -ge 2 ] || { echo "install: FAIL — --profile requires a directory" >&2; usage >&2; exit 1; }
      PROFILE_ARG="$2"; shift 2
      ;;
    --list-profiles) LIST_PROFILES=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "install: FAIL — unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

PROFILE_DIRS=()
add_profile() {
  local candidate="$1" existing
  [ -n "$candidate" ] || return 0
  if [ -d "$candidate" ]; then
    candidate="$(cd "$candidate" && pwd -P)"
  fi
  # Bash 3.2 with `set -u` treats an empty array expansion as unbound. The
  # `+word` form keeps the first add_profile call safe while preserving normal
  # quoted-array behavior after an entry exists.
  for existing in ${PROFILE_DIRS[@]+"${PROFILE_DIRS[@]}"}; do
    [ "$existing" = "$candidate" ] && return 0
  done
  PROFILE_DIRS+=("$candidate")
}
is_profile_dir() {
  [ -d "$1" ] && {
    [ -f "$1/.credentials.json" ] ||
    [ -d "$1/projects" ] ||
    [ -f "$1/agent-team-manifest.json" ]
  }
}

# The default profile remains a candidate even on a fresh machine where it has
# not been created yet. Alternate conventional profile roots are counted only
# when they carry Claude profile state, so unrelated directories such as
# ~/.claude-mem and ~/.claude-code-gui are not false positives.
add_profile "$HOME/.claude"
for candidate in "$HOME"/.claude-*; do
  is_profile_dir "$candidate" && add_profile "$candidate"
done
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  add_profile "$CLAUDE_CONFIG_DIR"
fi
# Non-conventional profile paths cannot be inferred safely. A caller can make
# them visible to --list-profiles and ambiguity checks as a colon-separated list.
if [ -n "${AGENT_TEAM_PROFILE_DIRS:-}" ]; then
  old_ifs="$IFS"; IFS=':'
  for candidate in $AGENT_TEAM_PROFILE_DIRS; do add_profile "$candidate"; done
  IFS="$old_ifs"
fi

if [ "$LIST_PROFILES" -eq 1 ]; then
  echo "profiles: ${#PROFILE_DIRS[@]} detected"
  for candidate in "${PROFILE_DIRS[@]}"; do
    marker=""
    [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ "$candidate" = "$CLAUDE_CONFIG_DIR" ] && marker=" (CLAUDE_CONFIG_DIR)"
    echo "  $candidate$marker"
  done
  exit 0
fi

if [ -n "$PROFILE_ARG" ]; then
  CLAUDE_DIR="$PROFILE_ARG"
elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  CLAUDE_DIR="$CLAUDE_CONFIG_DIR"
elif [ "${#PROFILE_DIRS[@]}" -gt 1 ]; then
  echo "$MODE: FAIL — multiple Claude profiles detected; select one explicitly:" >&2
  for candidate in "${PROFILE_DIRS[@]}"; do
    if [ "$MODE" = "check" ]; then
      echo "  bash install.sh --check --profile \"$candidate\"" >&2
    else
      echo "  bash install.sh --profile \"$candidate\"" >&2
    fi
  done
  exit 1
else
  CLAUDE_DIR="${PROFILE_DIRS[0]}"
fi

# Hooks are referenced by an absolute "$HOME/.claude/hooks/..." path baked into
# agent frontmatter, and Claude Code does NOT reliably export CLAUDE_CONFIG_DIR
# to hook subprocesses — so hooks must live at that fixed location regardless of
# which config dir the agents install into, or a non-default CLAUDE_CONFIG_DIR
# install would point agents at hooks that aren't there. Agents/skills/manifest
# follow CLAUDE_DIR; hooks are pinned here.
HOOKS_DIR="$HOME/.claude/hooks"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CLAUDE_DIR/backups/agent-team-$STAMP"
MANIFEST="$CLAUDE_DIR/agent-team-manifest.json"

fail() { echo "$MODE: FAIL — $*" >&2; exit 1; }
warn() { echo "$MODE: WARNING — $*" >&2; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
frontmatter_value() { # $1 file, $2 key
  awk -v key="$2" '/^---$/{n++; next} n==1 && $1==key":"{sub($1"[[:space:]]*", ""); print; exit}' "$1"
}
HOOK_FILES="agent-team-secrets.sh agent-team-audit.sh agent-team-cost.sh agent-team-dispatch-guard.sh agent-team-plugin-router.sh model-rates.json agent-model-defaults.json"
# Approve-intent trust model (2026-07-12 spec): the command-gating policy hooks
# are retired. On install they are backed up, then PURGED from the hooks dir;
# --check fails with a RETIRED finding if any reappears.
RETIRED_HOOK_FILES="agent-team-policy.sh agent-team-policy-lib.sh agent-team-policy-mutations.sh"
POLICY_KEYS="$REPO/policy/KEYS.md"
FRAMEWORK_PIN="$REPO/SKILLS-FRAMEWORK"

# --- validation (nothing is touched until all of this passes) ---
command -v jq >/dev/null 2>&1 || fail "jq is required"
[ -f "$REPO/hooks/agent-team-secrets.sh" ] || fail "hooks/agent-team-secrets.sh is missing from repo"
[ -f "$REPO/hooks/agent-team-audit.sh" ] || fail "hooks/agent-team-audit.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-secrets.sh" || fail "secrets guard failed bash -n"
bash -n "$REPO/hooks/agent-team-audit.sh" || fail "audit hook failed bash -n"
[ -f "$REPO/hooks/agent-team-cost.sh" ] || fail "hooks/agent-team-cost.sh is missing from repo"
[ -f "$REPO/hooks/model-rates.json" ] || fail "hooks/model-rates.json is missing from repo"
bash -n "$REPO/hooks/agent-team-cost.sh" || fail "cost hook failed bash -n"
[ -f "$REPO/hooks/agent-team-dispatch-guard.sh" ] || fail "hooks/agent-team-dispatch-guard.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-dispatch-guard.sh" || fail "dispatch guard failed bash -n"
[ -f "$REPO/hooks/agent-team-plugin-router.sh" ] || fail "hooks/agent-team-plugin-router.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-plugin-router.sh" || fail "plugin router failed bash -n"
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
# Telemetry (2026-07-13 spec, D2 resolution): the committed role->pin map must
# exactly match what agents/*.md frontmatter says, so it can never silently
# diverge — same drift-test pattern as the hash-identical coding-standards copies.
[ -f "$REPO/hooks/agent-model-defaults.json" ] || fail "hooks/agent-model-defaults.json is missing from repo"
jq empty "$REPO/hooks/agent-model-defaults.json" || fail "agent-model-defaults.json is not valid JSON"
EXPECTED_DEFAULTS="$(for f in "$REPO"/agents/*.md; do
  printf '%s\t%s\n' "$(frontmatter_value "$f" name)" "$(frontmatter_value "$f" model)"
done | jq -R -n '[inputs | select(length > 0) | split("\t") | {(.[0]): .[1]}] | add')"
COMMITTED_DEFAULTS="$(jq -S '.roles' "$REPO/hooks/agent-model-defaults.json")"
[ "$(printf '%s' "$EXPECTED_DEFAULTS" | jq -S .)" = "$COMMITTED_DEFAULTS" ] \
  || fail "agent-model-defaults.json .roles does not match agents/*.md frontmatter pins — regenerate it"
jq -e --argjson roles "$COMMITTED_DEFAULTS" '
  .models as $M | [$roles[] | in($M)] | all
' "$REPO/hooks/model-rates.json" >/dev/null \
  || fail "agent-model-defaults.json: every pin must exist in model-rates.json"
[ -f "$REPO/tools/agent-team-scoreboard.sh" ] || fail "tools/agent-team-scoreboard.sh is missing from repo"
bash -n "$REPO/tools/agent-team-scoreboard.sh" || fail "scoreboard script failed bash -n"
# The outer installer runs these once. Sandbox installs launched by
# test_install_skills.sh inherit AGENT_TEAM_SKIP_INSTALL_TEST=1 so they exercise
# skill/install behavior without multiplying the unrelated hook suites.
if [ -z "${AGENT_TEAM_SKIP_INSTALL_TEST:-}" ]; then
  bash "$REPO/tests/test_secrets_hook.sh" >/dev/null || fail "secrets guard tests failed — run tests/test_secrets_hook.sh to see which"
  bash "$REPO/tests/test_audit_hook.sh" >/dev/null || fail "audit hook tests failed — run tests/test_audit_hook.sh to see which"
  bash "$REPO/tests/test_agent_frontmatter.sh" >/dev/null || fail "agent frontmatter tests failed — run tests/test_agent_frontmatter.sh to see which"
  bash "$REPO/tests/test_install_retire.sh" >/dev/null || fail "install-retire tests failed — run tests/test_install_retire.sh to see which"
  bash "$REPO/tests/test_cost_hook.sh" >/dev/null || fail "cost hook tests failed — run tests/test_cost_hook.sh to see which"
  bash "$REPO/tests/test_scoreboard.sh" >/dev/null || fail "scoreboard tests failed — run tests/test_scoreboard.sh to see which"
  bash "$REPO/tests/test_dispatch_guard.sh" >/dev/null || fail "dispatch guard tests failed — run tests/test_dispatch_guard.sh to see which"
  bash "$REPO/tests/test_plugin_mode.sh" >/dev/null || fail "plugin-mode tests failed — run tests/test_plugin_mode.sh to see which"
  bash "$REPO/tests/test_chatgpt_plugin.sh" >/dev/null || fail "ChatGPT plugin tests failed — run tests/test_chatgpt_plugin.sh to see which"
  bash "$REPO/tests/test_codex_profiles.sh" >/dev/null || fail "Codex profile tests failed — run tests/test_codex_profiles.sh to see which"
  bash "$REPO/tests/test_decision_discipline_drift.sh" >/dev/null || fail "decision-discipline drift test failed — run tests/test_decision_discipline_drift.sh to see which"
  bash "$REPO/tests/test_orchestrator_autonomy.sh" >/dev/null || fail "orchestrator autonomy test failed — run tests/test_orchestrator_autonomy.sh to see which"
  bash "$REPO/tests/test_closeout_audit.sh" >/dev/null || fail "closeout audit test failed — run tests/test_closeout_audit.sh to see which"
  bash "$REPO/tests/test_completion_contract.sh" >/dev/null || fail "completion contract test failed — run tests/test_completion_contract.sh to see which"
  bash "$REPO/tests/test_completion_lint.sh" >/dev/null || fail "completion lint test failed — run tests/test_completion_lint.sh to see which"
fi
[ -f "$POLICY_KEYS" ] || fail "policy/KEYS.md is missing from repo"
[ -f "$FRAMEWORK_PIN" ] || fail "SKILLS-FRAMEWORK is missing from repo"
FRAMEWORK_REVISION="$(sed -n 's/^revision:[[:space:]]*//p' "$FRAMEWORK_PIN")"
printf '%s' "$FRAMEWORK_REVISION" | grep -qE '^[a-f0-9]{40}$' \
  || fail "SKILLS-FRAMEWORK: revision must be a full 40-character commit SHA"

# --- vendored skills validation (before anything is copied) ---
for d in "$REPO"/skills/*/; do
  name="$(basename "$d")"
  sm="$d/SKILL.md"
  [ -f "$sm" ] || fail "skills/$name has no SKILL.md"
  fm="$(awk '/^---$/{n++; next} n==1{print}' "$sm")"
  printf '%s\n' "$fm" | grep -qE '^name:' || fail "skills/$name/SKILL.md: missing frontmatter 'name:'"
  printf '%s\n' "$fm" | grep -qE '^description:' || fail "skills/$name/SKILL.md: missing frontmatter 'description:'"
  smname="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p')"
  [ "$smname" = "$name" ] || fail "skills/$name/SKILL.md: name '$smname' != directory '$name'"
  printf '%s' "$name" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$' \
    || fail "skills/$name: name violates Agent Skills naming rules"
  [ "${#name}" -le 64 ] || fail "skills/$name: name exceeds 64 characters"
  description="$(frontmatter_value "$sm" description)"
  [ "${#description}" -le 1024 ] || fail "skills/$name: description exceeds 1024 characters"

  while IFS= read -r link; do
    [ -n "$link" ] || continue
    case "$link" in http*|mailto:*|/*) continue ;; esac
    [ -f "$d$link" ] || fail "skills/$name/SKILL.md: dangling relative link '$link'"
  done <<EOF
$(grep -oE '\]\([^)#][^)]*\)' "$sm" | sed 's/^](//; s/)$//' || true)
EOF
done

# The consumer-owned project-policy instance must cover every active registry
# key. A missing value would make behavior depend on an invisible judgment
# fallback even though this workforce ships an explicit organization policy.
PROJECT_POLICY="$REPO/skills/project-policy/SKILL.md"
[ -f "$PROJECT_POLICY" ] || fail "skills/project-policy/SKILL.md is missing"
while IFS= read -r key; do
  [ -n "$key" ] || continue
  grep -qE "^\\*\\*$key( \\(inherited\\))?\\*\\*" "$PROJECT_POLICY" \
    || fail "project-policy is missing registered key '$key'"
done <<EOF
$(grep -oE '^- [a-z-]+' "$POLICY_KEYS" | sed 's/^- //' || true)
EOF

# Built-in skills ship with the Claude Code client itself and have no
# SKILL.md on disk anywhere (not under ~/.claude/skills/, not in the plugin
# cache) — "verify" is one of these. Listed explicitly so the check below
# stays a real resolution check rather than a rubber stamp.
BUILTIN_SKILLS=" verify run init review security-review code-review update-config keybindings-help "

resolve_skill() { # $1 skill ref (bare or ns:name) -> 0 if found
  case "$1" in
    *:*)
      ns="${1%%:*}"; sk="${1#*:}"
      ls "$CLAUDE_DIR/plugins/cache/"*/"$ns"/*/skills/"$sk"/SKILL.md >/dev/null 2>&1
      ;;
    *)
      case "$BUILTIN_SKILLS" in
        *" $1 "*) return 0 ;;
      esac
      [ -f "$REPO/skills/$1/SKILL.md" ] || [ -f "$CLAUDE_DIR/skills/$1/SKILL.md" ]
      ;;
  esac
}

# Framework dependency and policy contracts are validated independently of
# which agents happen to preload a skill. This prevents a seemingly-unused
# skill from shipping with a broken requires: edge or an unknown policy key.
for d in "$REPO"/skills/*/; do
  name="$(basename "$d")"
  sm="$d/SKILL.md"
  requires="$(frontmatter_value "$sm" requires | tr -d '[],')"
  for required in $requires; do
    resolve_skill "$required" \
      || fail "skills/$name/SKILL.md: requires '$required' but it does not resolve"
  done
  while IFS= read -r token; do
    [ -n "$token" ] || continue
    key="${token#policy:}"
    grep -qE "^- $key " "$POLICY_KEYS" \
      || fail "skills/$name/SKILL.md: unregistered policy key '$key'"
  done <<EOF
$(grep -ohE 'policy:[a-z-]+' "$sm" | sort -u || true)
EOF
done

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

# Skills invoked situationally via the Skill tool rather than preloaded in an
# agent's frontmatter are invisible to the loop above, so validate them here.
for s in interviewing convene-panel ux-to-ui-design op-migration; do
  resolve_skill "$s" || fail "situational skill '$s' does not resolve to an installed skill"
done

# The sandbox install-skills test itself invokes install.sh against its own
# throwaway HOME; without this guard, that inner install.sh run would reach
# this same line and spawn another copy of the test — unbounded recursion.
# The test exports AGENT_TEAM_SKIP_INSTALL_TEST=1 before invoking install.sh
# (see tests/test_install_skills.sh), so the inner run skips this check.
[ -n "${AGENT_TEAM_SKIP_INSTALL_TEST:-}" ] || bash "$REPO/tests/test_install_skills.sh" >/dev/null || fail "install-skills tests failed — run tests/test_install_skills.sh to see which"

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
  recorded_framework="$(jq -r '.skills_framework_revision // empty' "$MANIFEST")"
  if [ "$recorded_framework" != "$FRAMEWORK_REVISION" ]; then
    echo "check: STALE — skills framework pin changed since the last install; re-run install"
    drift=1
  fi
  while IFS="$(printf '\t')" read -r rel recorded; do
    [ -n "$rel" ] || continue
    case "$rel" in
      agents/*) inst="$CLAUDE_DIR/agents/$(basename "$rel")" ;;
      hooks/*)  inst="$HOOKS_DIR/$(basename "$rel")" ;;
      skills/*) inst="$CLAUDE_DIR/skills/${rel#skills/}" ;;
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
  while IFS= read -r rel; do
    rel="skills/${rel#./}"
    jq -e --arg k "$rel" '.files[$k] != null' "$MANIFEST" >/dev/null \
      || { echo "check: NEW — $rel exists in the repo but was never installed"; drift=1; }
  done <<EOF
$(cd "$REPO/skills" && find . -type f)
EOF
  for h in $RETIRED_HOOK_FILES; do
    [ -f "$HOOKS_DIR/$h" ] && { echo "check: RETIRED — $HOOKS_DIR/$h is a retired policy hook and must be purged; re-run install"; drift=1; }
  done
  if [ "$drift" -eq 0 ]; then
    echo "check: OK — installed team matches repo build $(jq -r '.commit' "$MANIFEST") (installed $(jq -r '.installed_at' "$MANIFEST"))"
    exit 0
  fi
  fail "drift detected (lines above). Reconcile any hand edits back into the repo, then re-run 'bash install.sh'"
fi

# --- backup ---
mkdir -p "$BACKUP" "$CLAUDE_DIR/agents" "$HOOKS_DIR" "$CLAUDE_DIR/skills" "$CLAUDE_DIR/logs" || fail "cannot create target directories"

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
# Retired policy hooks: back up any installed copy (so restore() can put the
# machine back exactly as it was on a failed install), then purge post-install.
RETIRED_PRESENT=""
for h in $RETIRED_HOOK_FILES; do
  [ -f "$HOOKS_DIR/$h" ] && { cp "$HOOKS_DIR/$h" "$BACKUP/"; RETIRED_PRESENT="$RETIRED_PRESENT $h"; }
done
PREEXISTING_COST=0
PREEXISTING_RATES=0
PREEXISTING_GUARD=0
PREEXISTING_DEFAULTS=0
[ -f "$HOOKS_DIR/agent-team-cost.sh" ] && { cp "$HOOKS_DIR/agent-team-cost.sh" "$BACKUP/"; PREEXISTING_COST=1; }
[ -f "$HOOKS_DIR/model-rates.json" ] && { cp "$HOOKS_DIR/model-rates.json" "$BACKUP/"; PREEXISTING_RATES=1; }
[ -f "$HOOKS_DIR/agent-team-dispatch-guard.sh" ] && { cp "$HOOKS_DIR/agent-team-dispatch-guard.sh" "$BACKUP/"; PREEXISTING_GUARD=1; }
[ -f "$HOOKS_DIR/agent-model-defaults.json" ] && { cp "$HOOKS_DIR/agent-model-defaults.json" "$BACKUP/"; PREEXISTING_DEFAULTS=1; }

# Skills files are nested (skills/<name>/<relpath>), unlike the flat agents/
# and hooks/ trees above, so they get their own backup loop keyed by relative
# path rather than basename — the case-by-basename scheme in restore() can't
# express nested destinations.
PREEXISTING_SKILLS=""
while IFS= read -r rel; do
  rel="${rel#./}"
  inst="$CLAUDE_DIR/skills/$rel"
  if [ -f "$inst" ]; then
    mkdir -p "$BACKUP/skills/$(dirname "$rel")"
    cp "$inst" "$BACKUP/skills/$rel"
    PREEXISTING_SKILLS="$PREEXISTING_SKILLS $rel"
  fi
done <<EOF
$(cd "$REPO/skills" && find . -type f)
EOF

# Files managed by the previous manifest but removed from the current vendored
# tree are retired on this install. Back them up with the rest so a later copy
# failure can restore the exact previous installation.
RETIRED_SKILLS=""
if [ -f "$MANIFEST" ] && jq empty "$MANIFEST" 2>/dev/null; then
  while IFS= read -r managed; do
    case "$managed" in
      skills/*)
        rel="${managed#skills/}"
        inst="$CLAUDE_DIR/skills/$rel"
        if [ ! -f "$REPO/skills/$rel" ] && [ -f "$inst" ]; then
          mkdir -p "$BACKUP/skills/$(dirname "$rel")"
          cp "$inst" "$BACKUP/skills/$rel"
          RETIRED_SKILLS="$RETIRED_SKILLS $rel"
        fi
        ;;
    esac
  done <<EOF
$(jq -r '.files | keys[]' "$MANIFEST")
EOF
fi

restore() {
  echo "install: restoring backup from $BACKUP" >&2
  for b in "$BACKUP"/*; do
    [ -f "$b" ] || continue
    case "$(basename "$b")" in
      agent-team-policy.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-policy-lib.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-policy-mutations.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-secrets.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-audit.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-plugin-router.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-cost.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-dispatch-guard.sh) cp "$b" "$HOOKS_DIR/" ;;
      model-rates.json) cp "$b" "$HOOKS_DIR/" ;;
      agent-model-defaults.json) cp "$b" "$HOOKS_DIR/" ;;
      *.md) cp "$b" "$CLAUDE_DIR/agents/" ;;
    esac
  done
  if [ -d "$BACKUP/skills" ]; then
    while IFS= read -r b; do
      rel="${b#"$BACKUP"/skills/}"
      mkdir -p "$CLAUDE_DIR/skills/$(dirname "$rel")"
      cp "$b" "$CLAUDE_DIR/skills/$rel"
    done <<EOF
$(find "$BACKUP/skills" -type f 2>/dev/null)
EOF
  fi
}

# Undo whatever THIS run freshly installed with no pre-existing version to
# roll back to, so a failed fresh install reverts to "nothing installed"
# instead of leaving a partial (and potentially broken) install behind.
# Only ever touches the exact files this installer manages — never anything
# else that happens to live in $CLAUDE_DIR/agents or $HOOKS_DIR.
cleanup_fresh() {
  for f in "$REPO"/agents/*.md; do
    bn="$(basename "$f")"
    case " $PREEXISTING_AGENTS " in
      *" $bn "*) : ;; # was pre-existing; restore() already handled it
      *) rm -f "$CLAUDE_DIR/agents/$bn" ;;
    esac
  done
  for h in $RETIRED_HOOK_FILES; do
    case " $RETIRED_PRESENT " in
      *" $h "*) : ;;                       # was present pre-install; restore() put it back
      *) rm -f "$HOOKS_DIR/$h" ;;
    esac
  done
  [ "$PREEXISTING_COST" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-cost.sh"
  [ "$PREEXISTING_RATES" -eq 0 ] && rm -f "$HOOKS_DIR/model-rates.json"
  [ "$PREEXISTING_GUARD" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-dispatch-guard.sh"
  [ "$PREEXISTING_DEFAULTS" -eq 0 ] && rm -f "$HOOKS_DIR/agent-model-defaults.json"
  while IFS= read -r rel; do
    rel="${rel#./}"
    case " $PREEXISTING_SKILLS " in
      *" $rel "*) : ;;                                  # pre-existing; restore() handled it
      *) rm -f "$CLAUDE_DIR/skills/$rel" ;;             # freshly installed; revert to "not here"
    esac
  done <<EOF
$(cd "$REPO/skills" && find . -type f)
EOF
}

# --- install ---
if ! cp "$REPO"/agents/*.md "$CLAUDE_DIR/agents/"; then restore; cleanup_fresh; fail "agent copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-secrets.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "secrets guard copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-audit.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "audit hook copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-plugin-router.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "plugin router copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-cost.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "cost hook copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-dispatch-guard.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "dispatch guard copy failed; rolled back"; fi
if ! cp "$REPO/hooks/model-rates.json" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "rates file copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-model-defaults.json" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "model defaults copy failed; rolled back"; fi
for rel in $RETIRED_SKILLS; do
  if ! rm -f "$CLAUDE_DIR/skills/$rel"; then restore; cleanup_fresh; fail "could not retire removed skill file $rel; rolled back"; fi
done
while IFS= read -r rel; do
  rel="${rel#./}"
  mkdir -p "$CLAUDE_DIR/skills/$(dirname "$rel")" || { restore; cleanup_fresh; fail "cannot create skills target dir for $rel; rolled back"; }
  if ! cp "$REPO/skills/$rel" "$CLAUDE_DIR/skills/$rel"; then restore; cleanup_fresh; fail "skill copy failed for $rel; rolled back"; fi
done <<EOF
$(cd "$REPO/skills" && find . -type f)
EOF
# Purge the retired policy hooks now that every copy above succeeded; a failed
# install never reaches this line, so restore() semantics are unaffected.
for h in $RETIRED_HOOK_FILES; do rm -f "$HOOKS_DIR/$h"; done
chmod +x "$HOOKS_DIR/agent-team-secrets.sh" || { restore; cleanup_fresh; fail "chmod of secrets guard failed; rolled back"; }
chmod +x "$HOOKS_DIR/agent-team-audit.sh" || { restore; cleanup_fresh; fail "chmod of audit hook failed; rolled back"; }
chmod +x "$HOOKS_DIR/agent-team-plugin-router.sh" || { restore; cleanup_fresh; fail "chmod of plugin router failed; rolled back"; }
chmod +x "$HOOKS_DIR/agent-team-cost.sh" || { restore; cleanup_fresh; fail "chmod of cost hook failed; rolled back"; }
chmod +x "$HOOKS_DIR/agent-team-dispatch-guard.sh" || { restore; cleanup_fresh; fail "chmod of dispatch guard failed; rolled back"; }

# --- manifest: record what this install shipped, so --check can detect drift
# and the orchestrator can announce its build at session start. Metadata only;
# a manifest failure does not undo an already-successful install.
COMMIT="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
TMP_MANIFEST="$(mktemp)"
{
  for f in "$REPO"/agents/*.md; do printf 'agents/%s\t%s\n' "$(basename "$f")" "$(sha "$f")"; done
  for h in $HOOK_FILES; do printf 'hooks/%s\t%s\n' "$h" "$(sha "$REPO/hooks/$h")"; done
  while IFS= read -r rel; do rel="${rel#./}"; printf 'skills/%s\t%s\n' "$rel" "$(sha "$REPO/skills/$rel")"; done <<EOF
$(cd "$REPO/skills" && find . -type f)
EOF
} | jq -R -n \
    --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg repo "$REPO" \
    --arg commit "$COMMIT" \
    --arg skills_framework_revision "$FRAMEWORK_REVISION" \
    '{installed_at: $at, repo: $repo, commit: $commit,
      skills_framework_revision: $skills_framework_revision,
      files: ([inputs | select(length > 0) | split("\t") | {(.[0]): .[1]}] | add)}' \
  > "$TMP_MANIFEST"
if jq empty "$TMP_MANIFEST" 2>/dev/null && cp "$TMP_MANIFEST" "$MANIFEST"; then
  rm -f "$TMP_MANIFEST"
else
  rm -f "$TMP_MANIFEST"
  warn "manifest write failed — install is fine, but 'install.sh --check' and the orchestrator's build line won't work until a successful re-install"
fi

AGENT_COUNT="$(find "$REPO/agents" -maxdepth 1 -name '*.md' -type f | wc -l | tr -d ' ')"
SKILL_COUNT="$(find "$REPO/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l | tr -d ' ')"
echo "install: OK — $AGENT_COUNT agents + $SKILL_COUNT skills installed into profile $CLAUDE_DIR, policy hook + cost hook installed, build $COMMIT recorded, backup at $BACKUP"
echo "install: verify any time with: bash install.sh --check --profile \"$CLAUDE_DIR\""
if [ "$CLAUDE_DIR" = "$HOME/.claude" ]; then
  echo "install: start the team with: claude --agent orchestrator"
else
  echo "install: start the team with: CLAUDE_CONFIG_DIR=\"$CLAUDE_DIR\" claude --agent orchestrator"
fi
