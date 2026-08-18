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
HOOK_FILES="agent-team-secrets.sh agent-team-audit.sh agent-team-cost.sh agent-team-dispatch-guard.sh agent-team-interrupt-guard.sh agent-team-report-guard.sh agent-team-worktree-guard.sh agent-team-lane-guard.sh agent-team-lane-paths.sh agent-team-guard-log.sh agent-team-plugin-router.sh agent-team-pin.sh agent-team-register.sh agent-team-register-lib.sh agent-team-register-writer.sh agent-team-workspace.sh agent-team-dispatch-change.sh agent_team_closeout.py debug_run_archiver.py session_start.py cost_report.py model-rates.json agent-model-defaults.json agent-team-budgets.json agent-team-lanes.json agent-team-register.json"
# --- version-pinned hook builds (2026-08-04) ------------------------------------
# Every hook is wired to one fixed path, and the harness re-reads that file on
# every tool call — so installing a repair used to rewrite the rules under every
# session already working, mid-task. Wheels changed on a moving bus, and a session
# failing against a defect could not tell that apart from the guard being edited
# beneath it.
#
# So the wired paths become generated shims, the real hooks live in an immutable
# per-build directory, and a session records its build on its first hook call and
# keeps it for the session's life. This install writes a NEW build and flips
# `current`; sessions already pinned are untouched, sessions started afterwards
# get this one. Nothing is ever edited in place. agent-team-pin.sh carries the
# resolution rule; these lists say which paths are entry points.
#
# The flat copies of everything else stay exactly as they were: absolute
# references to them exist in agent frontmatter and settings.json, and a pinned
# hook finds its own siblings (lanes.json, the guard-block log, the acceptance
# lint) inside its own build directory, so the enforcement path is fully pinned
# whether or not a flat copy is also present.
WIRED_BASH_HOOKS="agent-team-secrets.sh agent-team-audit.sh agent-team-cost.sh agent-team-dispatch-guard.sh agent-team-interrupt-guard.sh agent-team-report-guard.sh agent-team-worktree-guard.sh agent-team-lane-guard.sh agent-team-plugin-router.sh"
WIRED_PY_HOOKS="session_start.py agent_team_closeout.py debug_run_archiver.py auto-approve-safe-deletes.py"
# The payload every build carries: the hooks themselves plus the two tools the
# hooks resolve beside themselves.
BUILD_PAYLOAD="$HOOK_FILES auto-approve-safe-deletes.py lint_acceptance_checks.py"
VERSIONS_DIR="$HOOKS_DIR/agent-team-versions"
# Older builds are kept so a pinned session keeps working, and so a bad repair can
# be rolled back by flipping the symlink instead of reinstalling. One still named
# by a live pin is never removed regardless of age.
HOOK_BUILDS_KEPT=5
SHIM_MARKER="agent-team hook shim"
# Approve-intent trust model (2026-07-12 spec): the command-gating policy hooks
# are retired. On install they are backed up, then PURGED from the hooks dir;
# --check fails with a RETIRED finding if any reappears.
RETIRED_HOOK_FILES="agent-team-policy.sh agent-team-policy-lib.sh agent-team-policy-mutations.sh agent-team-process-assurance.py process_assurance.py lint_completion_claims.py"
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
[ -f "$REPO/hooks/agent-team-interrupt-guard.sh" ] || fail "hooks/agent-team-interrupt-guard.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-interrupt-guard.sh" || fail "interrupt guard failed bash -n"
[ -f "$REPO/hooks/agent-team-report-guard.sh" ] || fail "hooks/agent-team-report-guard.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-report-guard.sh" || fail "report guard failed bash -n"
[ -f "$REPO/hooks/agent-team-worktree-guard.sh" ] || fail "hooks/agent-team-worktree-guard.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-worktree-guard.sh" || fail "worktree guard failed bash -n"
[ -f "$REPO/hooks/agent-team-lane-guard.sh" ] || fail "hooks/agent-team-lane-guard.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-lane-guard.sh" || fail "lane guard failed bash -n"
[ -f "$REPO/hooks/agent-team-lane-paths.sh" ] || fail "hooks/agent-team-lane-paths.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-lane-paths.sh" || fail "lane path rules failed bash -n"
[ -f "$REPO/hooks/agent-team-guard-log.sh" ] || fail "hooks/agent-team-guard-log.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-guard-log.sh" || fail "guard block log failed bash -n"
# The work register and its library decide who owns a change; a broken one would
# refuse or admit every claim on the machine, so both are checked before install.
[ -f "$REPO/hooks/agent-team-register.sh" ] || fail "hooks/agent-team-register.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-register.sh" || fail "work register failed bash -n"
[ -f "$REPO/hooks/agent-team-register-lib.sh" ] || fail "hooks/agent-team-register-lib.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-register-lib.sh" || fail "work register library failed bash -n"
[ -f "$REPO/hooks/agent-team-register-writer.sh" ] || fail "hooks/agent-team-register-writer.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-register-writer.sh" || fail "work register writer slot failed bash -n"
# The dispatch guard sources its workspace half from beside itself, so a missing or
# broken one means no dispatch can be checked for workspace isolation at all.
[ -f "$REPO/hooks/agent-team-dispatch-change.sh" ] || fail "hooks/agent-team-dispatch-change.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-dispatch-change.sh" || fail "dispatch change gate failed bash -n"
# The workspace library is the one component that runs a mutating git command, so
# a syntax error in it would be a broken merge rather than a broken message.
[ -f "$REPO/hooks/agent-team-workspace.sh" ] || fail "hooks/agent-team-workspace.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-workspace.sh" || fail "change workspace library failed bash -n"
# The pin resolver is what every wired hook goes through. A broken one would take
# every guard on the machine down with it, so it is validated before anything is
# touched, exactly like the guards it fronts.
[ -f "$REPO/hooks/agent-team-pin.sh" ] || fail "hooks/agent-team-pin.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-pin.sh" || fail "hook pin resolver failed bash -n"
[ -f "$REPO/tools/lint_acceptance_checks.py" ] || fail "tools/lint_acceptance_checks.py is missing from repo"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
  "$REPO/tools/lint_acceptance_checks.py" || fail "acceptance-check lint failed Python syntax validation"
[ -f "$REPO/hooks/agent-team-plugin-router.sh" ] || fail "hooks/agent-team-plugin-router.sh is missing from repo"
bash -n "$REPO/hooks/agent-team-plugin-router.sh" || fail "plugin router failed bash -n"
[ -f "$REPO/hooks/agent_team_closeout.py" ] || fail "hooks/agent_team_closeout.py is missing from repo"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
  "$REPO/hooks/agent_team_closeout.py" || fail "closeout hook failed Python syntax validation"
[ -f "$REPO/hooks/debug_run_archiver.py" ] || fail "hooks/debug_run_archiver.py is missing from repo"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
  "$REPO/hooks/debug_run_archiver.py" || fail "debug-run archiver failed Python syntax validation"
[ -f "$REPO/hooks/session_start.py" ] || fail "hooks/session_start.py is missing from repo"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
  "$REPO/hooks/session_start.py" || fail "session-start hook failed Python syntax validation"
[ -f "$REPO/hooks/cost_report.py" ] || fail "hooks/cost_report.py is missing from repo"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
  "$REPO/hooks/cost_report.py" || fail "cost report tool failed Python syntax validation"
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
# Write lanes: the acceptance suite the builder may not author is configuration,
# so a broken or missing file must fail the install rather than degrade to a
# guard with no rule (the guard's own fallback is the strict default).
[ -f "$REPO/hooks/agent-team-lanes.json" ] || fail "hooks/agent-team-lanes.json is missing from repo"
jq empty "$REPO/hooks/agent-team-lanes.json" || fail "agent-team-lanes.json is not valid JSON"
jq -e '["acceptance_suite_paths", "doc_paths"]
       | all(. as $k | ($lanes[$k] | type == "array" and length > 0
             and (all(.[]; type == "string" and length > 0 and (startswith("/") | not)))))' \
  --argjson lanes "$(cat "$REPO/hooks/agent-team-lanes.json")" -n >/dev/null \
  || fail "agent-team-lanes.json: .acceptance_suite_paths and .doc_paths must each be a non-empty array of relative paths"
# The register's config carries the writer TTL and the stale-claim warning window.
# A malformed one would install silently and every read of it would fall back to a
# default nobody chose, so it is validated here like every other JSON config.
[ -f "$REPO/hooks/agent-team-register.json" ] || fail "hooks/agent-team-register.json is missing from repo"
jq empty "$REPO/hooks/agent-team-register.json" || fail "agent-team-register.json is not valid JSON"
# Dispatch budgets were in the same position: shipped as configuration, validated by
# nothing.
[ -f "$REPO/hooks/agent-team-budgets.json" ] || fail "hooks/agent-team-budgets.json is missing from repo"
jq empty "$REPO/hooks/agent-team-budgets.json" || fail "agent-team-budgets.json is not valid JSON"

[ -f "$REPO/tools/agent-team-scoreboard.sh" ] || fail "tools/agent-team-scoreboard.sh is missing from repo"
bash -n "$REPO/tools/agent-team-scoreboard.sh" || fail "scoreboard script failed bash -n"
# The outer installer runs these once. Sandbox installs launched by
# test_install_skills.sh inherit AGENT_TEAM_SKIP_INSTALL_TEST=1 so they exercise
# skill/install behavior without multiplying the unrelated hook suites.
# Install validates only what it installs: the hook suites that guard the
# artifacts being copied. The wider repo suite (plugin/Codex packaging, prose
# pins) runs in CI and before commits, never as an install hostage.
if [ -z "${AGENT_TEAM_SKIP_INSTALL_TEST:-}" ]; then
  bash "$REPO/tests/test_secrets_hook.sh" >/dev/null || fail "secrets guard tests failed — run tests/test_secrets_hook.sh to see which"
  bash "$REPO/tests/test_audit_hook.sh" >/dev/null || fail "audit hook tests failed — run tests/test_audit_hook.sh to see which"
  bash "$REPO/tests/test_agent_frontmatter.sh" >/dev/null || fail "agent frontmatter tests failed — run tests/test_agent_frontmatter.sh to see which"
  bash "$REPO/tests/test_install_retire.sh" >/dev/null || fail "install-retire tests failed — run tests/test_install_retire.sh to see which"
  bash "$REPO/tests/test_cost_hook.sh" >/dev/null || fail "cost hook tests failed — run tests/test_cost_hook.sh to see which"
  bash "$REPO/tests/test_dispatch_guard.sh" >/dev/null || fail "dispatch guard tests failed — run tests/test_dispatch_guard.sh to see which"
  bash "$REPO/tests/test_worktree_guard.sh" >/dev/null || fail "worktree guard tests failed — run tests/test_worktree_guard.sh to see which"
  # An agents/*.md edit that was never re-rendered ships a Codex surface that
  # contradicts the Claude surface. Cheap, deterministic, so gate on it here
  # rather than discovering it as unrelated-looking Codex breakage later.
  python3 "$REPO/scripts/render_codex_agents.py" --check >/dev/null 2>&1 \
    || fail "generated Codex profiles are stale — run: python3 scripts/render_codex_agents.py (then commit codex/)"
  bash "$REPO/tests/test_closeout_hook.sh" >/dev/null || fail "closeout hook test failed — run tests/test_closeout_hook.sh to see which"
  bash "$REPO/tests/test_cost_report.sh" >/dev/null || fail "cost report tests failed — run tests/test_cost_report.sh to see which"
fi
[ -f "$POLICY_KEYS" ] || fail "policy/KEYS.md is missing from repo"
[ -f "$FRAMEWORK_PIN" ] || fail "SKILLS-FRAMEWORK is missing from repo"
FRAMEWORK_REVISION="$(sed -n 's/^revision:[[:space:]]*//p' "$FRAMEWORK_PIN" | awk '{print $1}')"
[ -n "$FRAMEWORK_REVISION" ] || fail "SKILLS-FRAMEWORK: revision line is missing or empty"

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
    claude-fable-5|claude-opus-5|claude-opus-4-8|claude-sonnet-5) : ;;
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
for s in interviewing convene-panel ux-to-ui-design op-migration growing-the-team writing-skills closeout; do
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
  # Wired hooks are shims; the real file lives in the build this install recorded.
  recorded_build="$(jq -r '.hook_build // empty' "$MANIFEST")"
  is_wired_hook() { # $1 basename
    local w
    for w in $WIRED_BASH_HOOKS $WIRED_PY_HOOKS; do [ "$1" = "$w" ] && return 0; done
    return 1
  }
  recorded_framework="$(jq -r '.skills_framework_revision // empty' "$MANIFEST")"
  if [ "$recorded_framework" != "$FRAMEWORK_REVISION" ]; then
    echo "check: STALE — skills framework pin changed since the last install; re-run install"
    drift=1
  fi
  while IFS="$(printf '\t')" read -r rel recorded; do
    [ -n "$rel" ] || continue
    case "$rel" in
      agents/*) inst="$CLAUDE_DIR/agents/$(basename "$rel")" ;;
      hooks/*)
        hook_name="$(basename "$rel")"
        if is_wired_hook "$hook_name" && [ -n "$recorded_build" ] && [ -d "$VERSIONS_DIR/$recorded_build" ]; then
          inst="$VERSIONS_DIR/$recorded_build/$hook_name"
        else
          inst="$HOOKS_DIR/$hook_name"
        fi
        ;;
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
  if [ -z "$recorded_build" ]; then
    echo "check: STALE — this profile was installed before hook builds were version-pinned; re-run install"; drift=1
  elif [ ! -d "$VERSIONS_DIR/$recorded_build" ]; then
    echo "check: MISSING — the recorded hook build $VERSIONS_DIR/$recorded_build is gone"; drift=1
  else
    live_build="$(cd "$VERSIONS_DIR/current" 2>/dev/null && pwd -P || true)"
    if [ "$live_build" != "$(cd "$VERSIONS_DIR/$recorded_build" && pwd -P)" ]; then
      echo "check: DRIFT — $VERSIONS_DIR/current points at $live_build, not the recorded build $recorded_build"; drift=1
    fi
    for payload_file in $BUILD_PAYLOAD; do
      payload_src="$REPO/hooks/$payload_file"
      [ -f "$payload_src" ] || payload_src="$REPO/tools/$payload_file"
      if [ ! -f "$VERSIONS_DIR/$recorded_build/$payload_file" ]; then
        echo "check: MISSING — hook build $recorded_build has no $payload_file"; drift=1
      elif [ -f "$payload_src" ] && [ "$(sha "$VERSIONS_DIR/$recorded_build/$payload_file")" != "$(sha "$payload_src")" ]; then
        echo "check: STALE — repo $payload_file differs from the current hook build; re-run install"; drift=1
      fi
    done
  fi
  # A wired path that is not the generated shim is a hand edit that would silently
  # un-pin every session on this machine — exactly the failure being closed here.
  for wired in $WIRED_BASH_HOOKS $WIRED_PY_HOOKS; do
    if [ ! -f "$HOOKS_DIR/$wired" ]; then
      echo "check: MISSING — $HOOKS_DIR/$wired was installed but is gone"; drift=1
    elif ! grep -q "$SHIM_MARKER" "$HOOKS_DIR/$wired"; then
      echo "check: DRIFT — $HOOKS_DIR/$wired is not the generated shim (hand-edited under ~/.claude/?)"; drift=1
    fi
  done
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
PREEXISTING_SECRETS=0
PREEXISTING_AUDIT=0
PREEXISTING_ROUTER=0
PREEXISTING_WTGUARD=0
PREEXISTING_SESSIONSTART=0
PREEXISTING_ARCHIVER=0
PREEXISTING_RATES=0
PREEXISTING_GUARD=0
PREEXISTING_IGUARD=0
PREEXISTING_RGUARD=0
PREEXISTING_LINT=0
PREEXISTING_DEFAULTS=0
PREEXISTING_CLOSEOUT=0
PREEXISTING_COSTREPORT=0
PREEXISTING_BUDGETS=0
PREEXISTING_LANES=0
PREEXISTING_LANEGUARD=0
PREEXISTING_LANEPATHS=0
PREEXISTING_GUARDLOG=0
PREEXISTING_PIN=0
PREEXISTING_REGISTER=0
PREEXISTING_REGISTERLIB=0
PREEXISTING_REGISTERWRITER=0
PREEXISTING_REGISTERCONF=0
PREEXISTING_WORKSPACE=0
PREEXISTING_DISPATCHCHANGE=0
[ -f "$HOOKS_DIR/agent-team-secrets.sh" ] && { cp "$HOOKS_DIR/agent-team-secrets.sh" "$BACKUP/"; PREEXISTING_SECRETS=1; }
[ -f "$HOOKS_DIR/agent-team-audit.sh" ] && { cp "$HOOKS_DIR/agent-team-audit.sh" "$BACKUP/"; PREEXISTING_AUDIT=1; }
[ -f "$HOOKS_DIR/agent-team-plugin-router.sh" ] && { cp "$HOOKS_DIR/agent-team-plugin-router.sh" "$BACKUP/"; PREEXISTING_ROUTER=1; }
[ -f "$HOOKS_DIR/session_start.py" ] && { cp "$HOOKS_DIR/session_start.py" "$BACKUP/"; PREEXISTING_SESSIONSTART=1; }
[ -f "$HOOKS_DIR/debug_run_archiver.py" ] && { cp "$HOOKS_DIR/debug_run_archiver.py" "$BACKUP/"; PREEXISTING_ARCHIVER=1; }
[ -f "$HOOKS_DIR/agent-team-cost.sh" ] && { cp "$HOOKS_DIR/agent-team-cost.sh" "$BACKUP/"; PREEXISTING_COST=1; }
[ -f "$HOOKS_DIR/model-rates.json" ] && { cp "$HOOKS_DIR/model-rates.json" "$BACKUP/"; PREEXISTING_RATES=1; }
[ -f "$HOOKS_DIR/agent-team-dispatch-guard.sh" ] && { cp "$HOOKS_DIR/agent-team-dispatch-guard.sh" "$BACKUP/"; PREEXISTING_GUARD=1; }
[ -f "$HOOKS_DIR/agent-team-interrupt-guard.sh" ] && { cp "$HOOKS_DIR/agent-team-interrupt-guard.sh" "$BACKUP/"; PREEXISTING_IGUARD=1; }
[ -f "$HOOKS_DIR/agent-team-report-guard.sh" ] && { cp "$HOOKS_DIR/agent-team-report-guard.sh" "$BACKUP/"; PREEXISTING_RGUARD=1; }
[ -f "$HOOKS_DIR/agent-team-worktree-guard.sh" ] && { cp "$HOOKS_DIR/agent-team-worktree-guard.sh" "$BACKUP/"; PREEXISTING_WTGUARD=1; }
[ -f "$HOOKS_DIR/lint_acceptance_checks.py" ] && { cp "$HOOKS_DIR/lint_acceptance_checks.py" "$BACKUP/"; PREEXISTING_LINT=1; }
[ -f "$HOOKS_DIR/agent-model-defaults.json" ] && { cp "$HOOKS_DIR/agent-model-defaults.json" "$BACKUP/"; PREEXISTING_DEFAULTS=1; }
[ -f "$HOOKS_DIR/agent_team_closeout.py" ] && { cp "$HOOKS_DIR/agent_team_closeout.py" "$BACKUP/"; PREEXISTING_CLOSEOUT=1; }
[ -f "$HOOKS_DIR/cost_report.py" ] && { cp "$HOOKS_DIR/cost_report.py" "$BACKUP/"; PREEXISTING_COSTREPORT=1; }
[ -f "$HOOKS_DIR/agent-team-budgets.json" ] && { cp "$HOOKS_DIR/agent-team-budgets.json" "$BACKUP/"; PREEXISTING_BUDGETS=1; }
[ -f "$HOOKS_DIR/agent-team-lanes.json" ] && { cp "$HOOKS_DIR/agent-team-lanes.json" "$BACKUP/"; PREEXISTING_LANES=1; }
[ -f "$HOOKS_DIR/agent-team-lane-guard.sh" ] && { cp "$HOOKS_DIR/agent-team-lane-guard.sh" "$BACKUP/"; PREEXISTING_LANEGUARD=1; }
[ -f "$HOOKS_DIR/agent-team-lane-paths.sh" ] && { cp "$HOOKS_DIR/agent-team-lane-paths.sh" "$BACKUP/"; PREEXISTING_LANEPATHS=1; }
[ -f "$HOOKS_DIR/agent-team-guard-log.sh" ] && { cp "$HOOKS_DIR/agent-team-guard-log.sh" "$BACKUP/"; PREEXISTING_GUARDLOG=1; }
[ -f "$HOOKS_DIR/agent-team-pin.sh" ] && { cp "$HOOKS_DIR/agent-team-pin.sh" "$BACKUP/"; PREEXISTING_PIN=1; }
[ -f "$HOOKS_DIR/agent-team-register.sh" ] && { cp "$HOOKS_DIR/agent-team-register.sh" "$BACKUP/"; PREEXISTING_REGISTER=1; }
[ -f "$HOOKS_DIR/agent-team-register-lib.sh" ] && { cp "$HOOKS_DIR/agent-team-register-lib.sh" "$BACKUP/"; PREEXISTING_REGISTERLIB=1; }
[ -f "$HOOKS_DIR/agent-team-register-writer.sh" ] && { cp "$HOOKS_DIR/agent-team-register-writer.sh" "$BACKUP/"; PREEXISTING_REGISTERWRITER=1; }
[ -f "$HOOKS_DIR/agent-team-register.json" ] && { cp "$HOOKS_DIR/agent-team-register.json" "$BACKUP/"; PREEXISTING_REGISTERCONF=1; }
[ -f "$HOOKS_DIR/agent-team-workspace.sh" ] && { cp "$HOOKS_DIR/agent-team-workspace.sh" "$BACKUP/"; PREEXISTING_WORKSPACE=1; }
[ -f "$HOOKS_DIR/agent-team-dispatch-change.sh" ] && { cp "$HOOKS_DIR/agent-team-dispatch-change.sh" "$BACKUP/"; PREEXISTING_DISPATCHCHANGE=1; }

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
      agent-team-interrupt-guard.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-report-guard.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-worktree-guard.sh) cp "$b" "$HOOKS_DIR/" ;;
      lint_acceptance_checks.py) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-process-assurance.py) cp "$b" "$HOOKS_DIR/" ;;
      process_assurance.py) cp "$b" "$HOOKS_DIR/" ;;
      agent_team_closeout.py) cp "$b" "$HOOKS_DIR/" ;;
      cost_report.py) cp "$b" "$HOOKS_DIR/" ;;
      session_start.py) cp "$b" "$HOOKS_DIR/" ;;
      debug_run_archiver.py) cp "$b" "$HOOKS_DIR/" ;;
      lint_completion_claims.py) cp "$b" "$HOOKS_DIR/" ;;
      model-rates.json) cp "$b" "$HOOKS_DIR/" ;;
      agent-model-defaults.json) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-budgets.json) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-lanes.json) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-lane-guard.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-lane-paths.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-guard-log.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-pin.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-register.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-register-lib.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-register-writer.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-register.json) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-workspace.sh) cp "$b" "$HOOKS_DIR/" ;;
      agent-team-dispatch-change.sh) cp "$b" "$HOOKS_DIR/" ;;
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
  [ "$PREEXISTING_IGUARD" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-interrupt-guard.sh"
  [ "$PREEXISTING_RGUARD" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-report-guard.sh"
  [ "$PREEXISTING_LINT" -eq 0 ] && rm -f "$HOOKS_DIR/lint_acceptance_checks.py"
  [ "$PREEXISTING_DEFAULTS" -eq 0 ] && rm -f "$HOOKS_DIR/agent-model-defaults.json"
  [ "$PREEXISTING_CLOSEOUT" -eq 0 ] && rm -f "$HOOKS_DIR/agent_team_closeout.py"
  [ "$PREEXISTING_COSTREPORT" -eq 0 ] && rm -f "$HOOKS_DIR/cost_report.py"
  [ "$PREEXISTING_BUDGETS" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-budgets.json"
  [ "$PREEXISTING_LANES" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-lanes.json"
  [ "$PREEXISTING_LANEGUARD" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-lane-guard.sh"
  [ "$PREEXISTING_SECRETS" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-secrets.sh"
  [ "$PREEXISTING_AUDIT" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-audit.sh"
  [ "$PREEXISTING_ROUTER" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-plugin-router.sh"
  [ "$PREEXISTING_WTGUARD" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-worktree-guard.sh"
  [ "$PREEXISTING_SESSIONSTART" -eq 0 ] && rm -f "$HOOKS_DIR/session_start.py"
  [ "$PREEXISTING_ARCHIVER" -eq 0 ] && rm -f "$HOOKS_DIR/debug_run_archiver.py"
  [ "$PREEXISTING_LANEPATHS" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-lane-paths.sh"
  [ "$PREEXISTING_GUARDLOG" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-guard-log.sh"
  [ "$PREEXISTING_PIN" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-pin.sh"
  [ "$PREEXISTING_REGISTER" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-register.sh"
  [ "$PREEXISTING_REGISTERLIB" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-register-lib.sh"
  [ "$PREEXISTING_REGISTERWRITER" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-register-writer.sh"
  [ "$PREEXISTING_REGISTERCONF" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-register.json"
  [ "$PREEXISTING_WORKSPACE" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-workspace.sh"
  [ "$PREEXISTING_DISPATCHCHANGE" -eq 0 ] && rm -f "$HOOKS_DIR/agent-team-dispatch-change.sh"
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
if ! cp "$REPO/hooks/agent-team-interrupt-guard.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "interrupt guard copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-report-guard.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "report guard copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-worktree-guard.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "worktree guard copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent_team_closeout.py" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "closeout hook copy failed; rolled back"; fi
if ! cp "$REPO/hooks/debug_run_archiver.py" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "debug-run archiver copy failed; rolled back"; fi
if ! cp "$REPO/hooks/session_start.py" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "session-start hook copy failed; rolled back"; fi
if ! cp "$REPO/hooks/cost_report.py" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "cost report tool copy failed; rolled back"; fi
if ! cp "$REPO/tools/auto-approve-safe-deletes.py" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "delete guard copy failed; rolled back"; fi
if ! cp "$REPO/tools/lint_acceptance_checks.py" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "acceptance-check lint copy failed; rolled back"; fi
if ! cp "$REPO/hooks/model-rates.json" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "rates file copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-model-defaults.json" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "model defaults copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-budgets.json" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "dispatch budgets copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-lanes.json" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "write lanes copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-lane-guard.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "lane guard copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-lane-paths.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "lane path rules copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-guard-log.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "guard block log copy failed; rolled back"; fi
# The pin resolver is the one file that is NOT version-pinned: it is what resolves
# the pin, so every shim sources it from the flat hooks dir by a stable path.
if ! cp "$REPO/hooks/agent-team-pin.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "hook pin resolver copy failed; rolled back"; fi
# The work register, its two libraries, and its config travel together: the
# register sources both libraries from beside itself and reads the config from
# beside itself, so a partial copy would leave a register that refuses every claim.
if ! cp "$REPO/hooks/agent-team-register.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "work register copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-register-lib.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "work register library copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-register-writer.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "work register writer slot copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-register.json" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "work register config copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-workspace.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "change workspace library copy failed; rolled back"; fi
if ! cp "$REPO/hooks/agent-team-dispatch-change.sh" "$HOOKS_DIR/"; then restore; cleanup_fresh; fail "dispatch change gate copy failed; rolled back"; fi
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
chmod +x "$HOOKS_DIR/agent-team-interrupt-guard.sh" || { restore; cleanup_fresh; fail "chmod of interrupt guard failed; rolled back"; }
chmod +x "$HOOKS_DIR/agent-team-report-guard.sh" || { restore; cleanup_fresh; fail "chmod of report guard failed; rolled back"; }
chmod +x "$HOOKS_DIR/agent_team_closeout.py" || { restore; cleanup_fresh; fail "chmod of closeout hook failed; rolled back"; }
chmod +x "$HOOKS_DIR/cost_report.py" || { restore; cleanup_fresh; fail "chmod of cost report tool failed; rolled back"; }
chmod +x "$HOOKS_DIR/auto-approve-safe-deletes.py" || { restore; cleanup_fresh; fail "chmod of delete guard failed; rolled back"; }
chmod +x "$HOOKS_DIR/agent-team-pin.sh" || { restore; cleanup_fresh; fail "chmod of hook pin resolver failed; rolled back"; }

# --- version-pinned hook build --------------------------------------------------
# This is the step that makes a repair safe to install while sessions are running:
# write a NEW immutable build, point the wired paths at "whichever build my session
# is pinned to", and only then flip `current`. A session already working keeps the
# build it started on; nothing it depends on is rewritten underneath it.
COMMIT="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
HOOK_BUILD="$STAMP-$COMMIT"
BUILD_DIR="$VERSIONS_DIR/$HOOK_BUILD"
mkdir -p "$BUILD_DIR" || { restore; cleanup_fresh; fail "cannot create hook build directory $BUILD_DIR; rolled back"; }
for payload_file in $BUILD_PAYLOAD; do
  payload_src="$REPO/hooks/$payload_file"
  [ -f "$payload_src" ] || payload_src="$REPO/tools/$payload_file"
  [ -f "$payload_src" ] || { restore; cleanup_fresh; fail "hook build payload $payload_file is missing from the repo; rolled back"; }
  cp "$payload_src" "$BUILD_DIR/$payload_file" \
    || { restore; cleanup_fresh; fail "hook build copy failed for $payload_file; rolled back"; }
done
chmod +x "$BUILD_DIR"/*.sh 2>/dev/null || true
chmod +x "$BUILD_DIR"/*.py 2>/dev/null || true
# What this build is, readable without the manifest — a pinned session names a
# directory, and whoever is debugging it should not have to guess what is in there.
printf 'build: %s\ncommit: %s\nrepo: %s\ninstalled_at: %s\n' \
  "$HOOK_BUILD" "$COMMIT" "$REPO" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$BUILD_DIR/BUILD" 2>/dev/null

# Generated shims replace the wired flat paths. Content depends only on the hook's
# name, so it is byte-identical across builds: the file the harness re-reads on
# every tool call stops changing, which is the whole point.
write_bash_shim() { # $1 hook name
  printf '#!/usr/bin/env bash\n# GENERATED by agent-workforce install.sh — %s. Do not edit; every install\n# rewrites it. It runs whichever installed build of this hook the calling session\n# is pinned to, so installing a repair never changes the rules under a session\n# that is already working. The rule, and why it exists, are in agent-team-pin.sh.\nHOOK_NAME="%s"\n# shellcheck source=/dev/null\n. "$(dirname "$0")/agent-team-pin.sh"\n' \
    "$SHIM_MARKER" "$1" > "$HOOKS_DIR/$1"
}
write_py_shim() { # $1 hook name
  sed -e "s/__HOOK_NAME__/$1/" -e "s/__SHIM_MARKER__/$SHIM_MARKER/" > "$HOOKS_DIR/$1" <<'PYSHIM'
#!/usr/bin/env python3
"""GENERATED by agent-workforce install.sh — __SHIM_MARKER__. Do not edit.

Runs whichever installed build of __HOOK_NAME__ the calling session is pinned to,
so installing a repair never changes the rules under a session already working.
The resolution rule lives in agent-team-pin.sh — one authority, not two.
"""
import json
import os
import subprocess
import sys

HOOK_NAME = "__HOOK_NAME__"
HOOKS_DIR = os.path.dirname(os.path.abspath(__file__))

payload = sys.stdin.read()
session = ""
try:
    parsed = json.loads(payload)
    if isinstance(parsed, dict):
        session = str(parsed.get("session_id") or "")
except ValueError:
    session = ""

resolved = subprocess.run(
    ["bash", os.path.join(HOOKS_DIR, "agent-team-pin.sh"), "--resolve", session],
    capture_output=True, text=True)
build = resolved.stdout.strip()
real = os.path.join(build, HOOK_NAME) if build else ""
if resolved.returncode != 0 or not build or not os.path.isfile(real):
    # Fail closed: an action nobody could check is the outcome this indirection
    # exists to prevent.
    sys.stderr.write(
        "agent-team hook pin: no installed build of %s could be resolved, so this "
        "action cannot be checked against any version of the rules. Blocking rather "
        "than failing open. Re-run: bash install.sh\n" % HOOK_NAME)
    sys.exit(2)

sys.exit(subprocess.run([sys.executable, real, *sys.argv[1:]],
                        input=payload, text=True).returncode)
PYSHIM
}
for wired in $WIRED_BASH_HOOKS; do
  write_bash_shim "$wired" || { restore; cleanup_fresh; fail "could not write the $wired shim; rolled back"; }
  chmod +x "$HOOKS_DIR/$wired" || { restore; cleanup_fresh; fail "chmod of the $wired shim failed; rolled back"; }
done
for wired in $WIRED_PY_HOOKS; do
  write_py_shim "$wired" || { restore; cleanup_fresh; fail "could not write the $wired shim; rolled back"; }
  chmod +x "$HOOKS_DIR/$wired" || { restore; cleanup_fresh; fail "chmod of the $wired shim failed; rolled back"; }
  python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
    "$HOOKS_DIR/$wired" || { restore; cleanup_fresh; fail "the generated $wired shim is not valid Python; rolled back"; }
done

# Flip last, atomically, and only once every copy above has succeeded: until this
# rename lands, a new session still resolves the previous build, so a half-written
# install is never a half-enforced machine.
#
# The rename is done with rename(2) via python3, NOT `mv`. When the destination is
# a symlink pointing at a directory — which `current` is on every install after the
# first — `mv` follows it and moves the new link INSIDE the old build, leaving
# `current` still aimed at the previous version. The second install then silently
# changes nothing, which is the most dangerous possible outcome for this mechanism:
# it looks installed and enforces the old rules. rename(2) replaces the link itself
# and never follows it.
if ln -s "$HOOK_BUILD" "$VERSIONS_DIR/.current.$$" 2>/dev/null \
   && python3 -c 'import os, sys; os.replace(sys.argv[1], sys.argv[2])' \
        "$VERSIONS_DIR/.current.$$" "$VERSIONS_DIR/current"; then
  :
else
  rm -f "$VERSIONS_DIR/.current.$$"
  restore; cleanup_fresh
  fail "could not point $VERSIONS_DIR/current at $HOOK_BUILD; rolled back"
fi

# Old builds are kept deliberately — a pinned session still runs one, and rolling
# a bad repair back is a symlink flip rather than a reinstall. Prune by age, and
# never remove the live build or one a pin still names, however old it is.
PINS_DIR="${AGENT_TEAM_PIN_DIR:-$HOME/.claude/state/agent-team-hookver}"
LIVE_BUILD="$(cd "$VERSIONS_DIR/current" 2>/dev/null && pwd -P)"
PINNED_BUILDS="$(cat "$PINS_DIR"/* 2>/dev/null || true)"
PRUNED=0
while IFS= read -r candidate; do
  [ -n "$candidate" ] || continue
  [ "$candidate" = "$LIVE_BUILD" ] && continue
  case "$PINNED_BUILDS" in *"$candidate"*) continue ;; esac
  rm -rf "$candidate" && PRUNED=$((PRUNED + 1))
done <<EOF
$(find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | tail -n +$((HOOK_BUILDS_KEPT + 1)))
EOF
echo "install: hook build $HOOK_BUILD is current ($(find "$VERSIONS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') kept, $PRUNED pruned); wired paths are shims that resolve each session's pinned build"

# --- settings: workforce-managed permission rules (idempotent, additive) ---
# Memory-directory writes were blocked live 2026-07-22 (a stale, factually
# wrong memory could not be corrected mid-session). A paste-this-doc fix is
# the quiet-documentation failure this repo exists to kill, so the installer
# owns the rule: merged into the profile's settings.json on every install,
# scoped to the memory directories only, never touching anything else there.
if python3 - "$CLAUDE_DIR" <<'PY'
import json, os, sys
profile = os.path.abspath(sys.argv[1])
path = os.path.join(profile, "settings.json")
try:
    with open(path) as f:
        doc = json.load(f)
except (OSError, ValueError):
    doc = {}
if not isinstance(doc, dict):
    sys.exit(1)  # unrecognizable settings: refuse to touch
perms = doc.setdefault("permissions", {})
if not isinstance(perms, dict):
    sys.exit(1)
allow = perms.setdefault("allow", [])
if not isinstance(allow, list):
    sys.exit(1)
changed = False
# 2026-07-22: file-permission checks match Edit(path) rules only — a
# Write(path) rule is dead config that warns at every session start. Plant
# Edit only, and remove the dead Write rule earlier installs planted.
dead = f"Write(/{profile}/projects/**/memory/**)"
if dead in allow:
    allow.remove(dead)
    changed = True
rule = f"Edit(/{profile}/projects/**/memory/**)"
if rule not in allow:
    allow.append(rule)
    changed = True
if changed:
    tmp = path + ".workforce-tmp"
    with open(tmp, "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)
PY
then
  echo "install: memory-write permission rules present in $CLAUDE_DIR/settings.json"
else
  warn "settings.json at $CLAUDE_DIR has an unexpected shape — memory-write permission rules NOT merged; fix the file and re-run install"
fi

# --- settings: delete-guard wiring (idempotent; canonical entry owned) -----
# 2026-07-22 (Jay): downstream config must never be a paste-this instruction.
# The guard binary ships into the hooks dir above; this ensures the CANONICAL
# wiring (profile hooks path, no matcher filter, so git deletions reach it
# too) exists in the profile's settings.json. Hand-added entries pointing at
# other paths are never touched — a duplicate fire is harmless because the
# guard only allows-or-abstains.
if python3 - "$CLAUDE_DIR" "$HOOKS_DIR/auto-approve-safe-deletes.py" <<'PY'
import json, os, sys
profile, guard = os.path.abspath(sys.argv[1]), sys.argv[2]
path = os.path.join(profile, "settings.json")
try:
    with open(path) as f:
        doc = json.load(f)
except (OSError, ValueError):
    doc = {}
if not isinstance(doc, dict):
    sys.exit(1)  # unrecognizable settings: refuse to touch
if guard in json.dumps(doc):
    sys.exit(0)  # canonical wiring already present — nothing to do
hooks = doc.setdefault("hooks", {})
if not isinstance(hooks, dict):
    sys.exit(1)
pre = hooks.setdefault("PreToolUse", [])
if not isinstance(pre, list):
    sys.exit(1)
pre.append({"matcher": "Bash", "hooks": [
    {"type": "command", "command": f"python3 {guard}", "timeout": 10}]})
tmp = path + ".workforce-tmp"
with open(tmp, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
then
  echo "install: delete-guard wiring present in $CLAUDE_DIR/settings.json"
else
  warn "settings.json at $CLAUDE_DIR has an unexpected shape — delete-guard wiring NOT merged; fix the file and re-run install"
fi

# --- command shim: one obvious command from anywhere -----------------------
# 2026-07-26 (Jay, test machine): `claude --agent orchestrator` looks
# equivalent to the launcher but silently drops --permission-mode
# bypassPermissions and the freshness pass — and both the README and this
# installer's old closing message taught exactly that command. The fix is to
# make the right way the easy way: ship an `agent-workforce` command onto
# PATH that execs this repo's launcher. Shim failure warns, never fails the
# install — the repo launcher always remains the fallback.
SHIM_DIR="$HOME/.local/bin"
SHIM="$SHIM_DIR/agent-workforce"
if mkdir -p "$SHIM_DIR" 2>/dev/null \
   && printf '#!/usr/bin/env bash\n# Installed by agent-workforce install.sh — always exec the repo launcher,\n# which self-updates and freshens the profile before starting the team.\nexec "%s/bin/agent-workforce" "$@"\n' "$REPO" > "$SHIM" 2>/dev/null \
   && chmod +x "$SHIM" 2>/dev/null; then
  echo "install: command shim installed at $SHIM"
  case ":$PATH:" in
    *":$SHIM_DIR:"*) : ;;
    *) warn "$SHIM_DIR is not on PATH — the 'agent-workforce' command will not resolve until you add: export PATH=\"$SHIM_DIR:\$PATH\"" ;;
  esac
else
  warn "could not install the command shim at $SHIM — start the team with $REPO/bin/agent-workforce instead"
fi

# --- manifest: record what this install shipped, so --check can detect drift
# and the orchestrator can announce its build at session start. Metadata only;
# a manifest failure does not undo an already-successful install.
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
    --arg hook_build "$HOOK_BUILD" \
    --arg skills_framework_revision "$FRAMEWORK_REVISION" \
    '{installed_at: $at, repo: $repo, commit: $commit,
      hook_build: $hook_build,
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
# Never recommend `claude --agent orchestrator` here: it starts the same
# orchestrator without bypassPermissions or the freshness check, and a
# degraded session gives no signal beyond the session-start tripwire.
if [ "$CLAUDE_DIR" = "$HOME/.claude" ]; then
  echo "install: start the team with: agent-workforce"
else
  echo "install: start the team with: CLAUDE_CONFIG_DIR=\"$CLAUDE_DIR\" agent-workforce"
fi
