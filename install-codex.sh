#!/usr/bin/env bash
# install-codex.sh — install the local Codex custom-agent profiles and policy runtime.
set -u

REPO="$(cd "$(dirname "$0")" && pwd)"
MODE="install"

usage() {
  cat <<'EOF'
Usage:
  bash install-codex.sh
  bash install-codex.sh --check

Installs named custom-agent profiles under ${CODEX_HOME:-$HOME/.codex}/agents,
direct-launch equivalents under ${CODEX_HOME:-$HOME/.codex}, and the role-policy
runtime under ${CODEX_HOME:-$HOME/.codex}/agent-workforce.
The ChatGPT/Codex plugin must be installed separately.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'install-codex: FAIL — unknown argument: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
done

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
AGENTS_DIR="$CODEX_DIR/agents"
RUNTIME_DIR="$CODEX_DIR/agent-workforce"
HOOKS_DIR="$RUNTIME_DIR/hooks"
ROOT_PROFILE_SOURCE="$REPO/codex/agent-workforce.config.toml"
ROOT_PROFILE_TARGET="$CODEX_DIR/agent-workforce.config.toml"
PROFILE_SOURCE="$REPO/codex/agents"
LAUNCH_PROFILE_SOURCE="$REPO/codex/profiles"
POLICY="$REPO/codex/model-policy.json"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CODEX_DIR/backups/agent-workforce-$STAMP"
BACKUP_CREATED=0

fail() { printf 'install-codex: FAIL — %s\n' "$*" >&2; exit 1; }
warn() { printf 'install-codex: WARNING — %s\n' "$*" >&2; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v bash >/dev/null 2>&1 || fail "bash is required by the role-policy hooks"
jq empty "$POLICY" >/dev/null 2>&1 || fail "codex/model-policy.json is not valid JSON"
python3 "$REPO/scripts/render_codex_agents.py" --check \
  || fail "generated Codex profiles are stale; run scripts/render_codex_agents.py"

HOOK_FILES="agent-team-secrets.sh agent-team-audit.sh agent-team-process-assurance.py process_assurance.py"

python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
  "$REPO/hooks/agent-team-process-assurance.py" || fail "process-assurance adapter failed Python syntax validation"
python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' \
  "$REPO/hooks/process_assurance.py" || fail "process-assurance engine failed Python syntax validation"

check_models() {
  [ -z "${AGENT_WORKFORCE_SKIP_MODEL_CHECK:-}" ] || return 0
  codex_bin="${CODEX_BIN:-}"
  if [ -z "$codex_bin" ] && [ -x /Applications/ChatGPT.app/Contents/Resources/codex ]; then
    codex_bin=/Applications/ChatGPT.app/Contents/Resources/codex
  fi
  if [ -z "$codex_bin" ] && command -v codex >/dev/null 2>&1; then
    codex_bin="$(command -v codex)"
  fi
  if [ -z "$codex_bin" ]; then
    warn "Codex executable not found; model availability was not checked"
    return 0
  fi
  catalog="$($codex_bin debug models 2>/dev/null)" || {
    warn "Codex model catalog was unavailable; profile files were still validated"
    return 0
  }
  for model in $(jq -r '[.profiles[].model] | unique[]' "$POLICY"); do
    printf '%s' "$catalog" | jq -e --arg model "$model" '.models[] | select(.slug == $model)' >/dev/null \
      || fail "required model '$model' is not available to this Codex login"
  done
}

check_models

if [ "$MODE" = "check" ]; then
  for legacy in "$AGENTS_DIR"/agent-workforce-*.toml; do
    [ ! -e "$legacy" ] || fail "obsolete hyphenated profile remains installed: $legacy"
  done
  for source in "$PROFILE_SOURCE"/*.toml; do
    target="$AGENTS_DIR/$(basename "$source")"
    [ -f "$target" ] || fail "missing installed profile: $target"
    cmp -s "$source" "$target" || fail "installed profile differs: $target"
  done
  for source in "$LAUNCH_PROFILE_SOURCE"/*.config.toml; do
    target="$CODEX_DIR/$(basename "$source")"
    [ -f "$target" ] || fail "missing installed direct-launch profile: $target"
    cmp -s "$source" "$target" || fail "installed direct-launch profile differs: $target"
  done
  for file in $HOOK_FILES; do
    [ -f "$HOOKS_DIR/$file" ] || fail "missing installed policy hook: $HOOKS_DIR/$file"
    cmp -s "$REPO/hooks/$file" "$HOOKS_DIR/$file" || fail "installed policy hook differs: $HOOKS_DIR/$file"
  done
  [ -f "$ROOT_PROFILE_TARGET" ] || fail "missing installed orchestrator profile: $ROOT_PROFILE_TARGET"
  cmp -s "$ROOT_PROFILE_SOURCE" "$ROOT_PROFILE_TARGET" \
    || fail "installed orchestrator profile differs: $ROOT_PROFILE_TARGET"
  printf 'install-codex check: OK — %s profiles match\n' "$(jq '.profiles | length' "$POLICY")"
  exit 0
fi

mkdir -p "$AGENTS_DIR" "$HOOKS_DIR"

backup_legacy_profile() { # $1 obsolete target
  target="$1"
  [ -e "$target" ] || return 0
  if [ "$BACKUP_CREATED" -eq 0 ]; then
    mkdir -p "$BACKUP"
    BACKUP_CREATED=1
  fi
  relative="${target#$CODEX_DIR/}"
  mkdir -p "$BACKUP/$(dirname "$relative")"
  mv "$target" "$BACKUP/$relative"
}

# Builds before 2026-07-14 generated hyphenated identifiers that Codex refuses
# at spawn time. Retire only this workforce-owned legacy namespace, preserving
# every replaced file in the normal install backup.
for legacy in "$AGENTS_DIR"/agent-workforce-*.toml; do
  backup_legacy_profile "$legacy"
done

backup_if_different() { # $1 source, $2 target
  source="$1"; target="$2"
  [ -e "$target" ] || return 0
  cmp -s "$source" "$target" && return 0
  if [ "$BACKUP_CREATED" -eq 0 ]; then
    mkdir -p "$BACKUP"
    BACKUP_CREATED=1
  fi
  relative="${target#$CODEX_DIR/}"
  mkdir -p "$BACKUP/$(dirname "$relative")"
  cp -p "$target" "$BACKUP/$relative"
}

for source in "$PROFILE_SOURCE"/*.toml; do
  target="$AGENTS_DIR/$(basename "$source")"
  backup_if_different "$source" "$target"
  cp "$source" "$target"
done

for source in "$LAUNCH_PROFILE_SOURCE"/*.config.toml; do
  target="$CODEX_DIR/$(basename "$source")"
  backup_if_different "$source" "$target"
  cp "$source" "$target"
done

backup_if_different "$ROOT_PROFILE_SOURCE" "$ROOT_PROFILE_TARGET"
cp "$ROOT_PROFILE_SOURCE" "$ROOT_PROFILE_TARGET"

for file in $HOOK_FILES; do
  source="$REPO/hooks/$file"
  target="$HOOKS_DIR/$file"
  backup_if_different "$source" "$target"
  cp "$source" "$target"
  chmod +x "$target"
done

MANIFEST="$RUNTIME_DIR/install-manifest.txt"
{
  printf 'schema=1\n'
  printf 'installed_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'profile_count=%s\n' "$(jq '.profiles | length' "$POLICY")"
  printf '%s  agent-workforce.config.toml\n' "$(sha "$ROOT_PROFILE_SOURCE")"
  for source in "$PROFILE_SOURCE"/*.toml; do
    printf '%s  agents/%s\n' "$(sha "$source")" "$(basename "$source")"
  done
  for source in "$LAUNCH_PROFILE_SOURCE"/*.config.toml; do
    printf '%s  %s\n' "$(sha "$source")" "$(basename "$source")"
  done
  for file in $HOOK_FILES; do
    printf '%s  agent-workforce/hooks/%s\n' "$(sha "$REPO/hooks/$file")" "$file"
  done
} > "$MANIFEST"

printf 'Installed %s Agent Workforce profiles into %s\n' "$(jq '.profiles | length' "$POLICY")" "$AGENTS_DIR"
[ "$BACKUP_CREATED" -eq 0 ] || printf 'Backed up replaced files under %s\n' "$BACKUP"
printf 'Start a new Codex task, open /hooks once, and trust the Agent Workforce role-policy hooks.\n'
