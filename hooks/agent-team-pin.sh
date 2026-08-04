#!/usr/bin/env bash
# agent-team-pin.sh — resolves WHICH build of a hook a session runs, so repairing
# the workforce never changes the rules under a session that is already working.
#
# The problem this exists for, from 2026-08-04: every role's hook is wired to one
# fixed path under ~/.claude/hooks, and the harness re-reads that file from disk on
# every tool call. Installing a repair therefore rewrote the enforcement of every
# live session mid-task — wheels changed on a moving bus. A session that failed
# five times against a defect could not tell that apart from a guard being edited
# underneath it, because both look identical from inside.
#
# The fix is one layer of indirection:
#   <hooks>/agent-team-worktree-guard.sh          a generated shim, content stable
#   <hooks>/agent-team-versions/<build>/...       immutable payload, never rewritten
#   <hooks>/agent-team-versions/current           symlink, flipped by install.sh
#   <pins>/<session-id>                           the build THIS session runs
#
# A session records its build on its first hook call — at session start in
# practice, since the session-start hook is itself wired through a shim — and
# keeps it for the session's life. Installing a repair writes a NEW build
# directory and flips `current`, which cannot affect an already-pinned session.
# Sessions started afterwards get the new build. Nothing is ever edited in place.
#
# Two entry points:
#   --resolve [session-id]   print the build directory for that session, or exit 1
#   sourced by a shim with HOOK_NAME set: read the payload from stdin, resolve the
#     build from its session id, and run <build>/$HOOK_NAME with the payload and
#     arguments passed through unchanged, propagating its exit status exactly.
#
# Fail-closed: a payload whose build cannot be resolved is a broken install, and
# an unenforced action is the outcome this indirection must never produce — so an
# unresolvable pin exits 2 (block) rather than allowing the call through.
set -u

# $0 is the shim (sourcing does not change it), so this is always the hooks dir.
AGENT_TEAM_HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_TEAM_VERSIONS_DIR="$AGENT_TEAM_HOOKS_DIR/agent-team-versions"
AGENT_TEAM_PINS_DIR="${AGENT_TEAM_PIN_DIR:-$HOME/.claude/state/agent-team-hookver}"

# The build `current` points at, as an absolute directory, or empty.
pin_current_build() {
  local target
  [ -L "$AGENT_TEAM_VERSIONS_DIR/current" ] || [ -d "$AGENT_TEAM_VERSIONS_DIR/current" ] || return 1
  target="$(cd "$AGENT_TEAM_VERSIONS_DIR/current" 2>/dev/null && pwd -P)" || return 1
  [ -n "$target" ] || return 1
  printf '%s' "$target"
}

# A session id is only usable as a file name when it cannot escape the pins dir.
pin_safe_session_id() { # $1 raw id
  case "$1" in
    ''|*/*|.|..) return 1 ;;
    *) printf '%s' "$1" ;;
  esac
}

# The build this session is pinned to, creating the pin on first sight. Written
# with a hard link from a temporary file: link creation fails when the name
# already exists, so two hooks racing at session start cannot produce two
# different answers — the first writer wins and every later reader agrees.
pin_resolve() { # $1 session id (may be empty) -> build dir, or exit 1
  local sid pin build tmp recorded
  build="$(pin_current_build)" || build=""
  sid="$(pin_safe_session_id "${1:-}")" || sid=""
  if [ -z "$sid" ]; then
    # No session to pin to (a CLI invocation, or a payload without an id): the
    # current build is the only defensible answer.
    [ -n "$build" ] || return 1
    printf '%s' "$build"
    return 0
  fi
  pin="$AGENT_TEAM_PINS_DIR/$sid"
  if [ -f "$pin" ]; then
    recorded="$(head -n1 "$pin" 2>/dev/null)"
    if [ -n "$recorded" ] && [ -d "$recorded" ]; then
      printf '%s' "$recorded"
      return 0
    fi
    # A pin naming a build that no longer exists is a pruned or hand-deleted
    # directory. Falling back to current is the honest repair; refusing every
    # remaining call in the session is not.
  fi
  [ -n "$build" ] || return 1
  if mkdir -p "$AGENT_TEAM_PINS_DIR" 2>/dev/null; then
    tmp="$AGENT_TEAM_PINS_DIR/.tmp.$$"
    if printf '%s\n' "$build" > "$tmp" 2>/dev/null; then
      ln "$tmp" "$pin" 2>/dev/null
      rm -f "$tmp"
    fi
    if [ -f "$pin" ]; then
      recorded="$(head -n1 "$pin" 2>/dev/null)"
      [ -n "$recorded" ] && [ -d "$recorded" ] && { printf '%s' "$recorded"; return 0; }
    fi
  fi
  # The pin could not be written (read-only state dir). The build is still known,
  # so run it — pinning is what protects a session from a mid-flight change, and
  # losing that protection is not a reason to refuse the work.
  printf '%s' "$build"
}

pin_unresolved() { # $1 what was being run
  # shellcheck source=/dev/null
  [ -r "$AGENT_TEAM_HOOKS_DIR/agent-team-guard-log.sh" ] && . "$AGENT_TEAM_HOOKS_DIR/agent-team-guard-log.sh"
  command -v guard_log >/dev/null 2>&1 && guard_log pin "${1:-unknown}" block "no resolvable hook build"
  printf 'agent-team hook pin: no installed build of %s could be resolved — %s/current is missing or broken, so this action cannot be checked against any version of the rules. Blocking rather than failing open. Re-run: bash install.sh\n' \
    "${1:-the hook}" "$AGENT_TEAM_VERSIONS_DIR" >&2
  exit 2
}

if [ "${1:-}" = "--resolve" ]; then
  BUILD="$(pin_resolve "${2:-}")" || { printf 'agent-team hook pin: unresolved\n' >&2; exit 1; }
  [ -n "$BUILD" ] || { printf 'agent-team hook pin: unresolved\n' >&2; exit 1; }
  printf '%s\n' "$BUILD"
  exit 0
fi

# --- shim mode: HOOK_NAME is set by the generated shim that sourced this file.
if [ -n "${HOOK_NAME:-}" ]; then
  PIN_INPUT="$(cat)"
  PIN_SESSION=""
  if command -v jq >/dev/null 2>&1; then
    PIN_SESSION="$(printf '%s' "$PIN_INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
  fi
  BUILD="$(pin_resolve "$PIN_SESSION")" || pin_unresolved "$HOOK_NAME"
  [ -n "$BUILD" ] || pin_unresolved "$HOOK_NAME"
  REAL="$BUILD/$HOOK_NAME"
  [ -x "$REAL" ] || [ -f "$REAL" ] || pin_unresolved "$HOOK_NAME"
  printf '%s' "$PIN_INPUT" | bash "$REAL" "$@"
  exit $?
fi

printf 'agent-team hook pin: nothing to do — call with --resolve, or source this file from a generated shim with HOOK_NAME set.\n' >&2
exit 1
