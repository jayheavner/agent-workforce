#!/usr/bin/env bash
# agent-team-lane-guard.sh <role> — confines a role's file authoring to the paths
# that role is for.
#
# Until 2026-08-03 every one of these boundaries was prose in the agent's own
# instructions: the scribe "writes only under docs/, plans/, and doc-inventory/",
# the architect drafts plans and skills, the test-author writes tests. Prose held
# only while the agent chose to honor it — and the incident that produced this
# guard began with a correct prose refusal being re-routed to a role with no
# boundary at all. A lane the agent cannot exceed is not the same kind of thing
# as a lane it is asked to respect.
#
# PreToolUse(Write|Edit|NotebookEdit) only. Reads are never restricted: every
# role must read the plan, the repository, and its own inputs.
#
# Known limit, stated rather than hidden: a role that also holds Bash can write
# through a redirect, a heredoc, or an in-place editor, and this guard does not
# see that. The closeout hook's change-keyed separation rules are the net behind
# it — git sees a shell-authored file even when no hook did.
#
# Lanes are configuration, not constants: agent-team-lanes.json ships the
# defaults and a project overrides them in its own .workforce/project.json,
# because these directory names are this repository's conventions and the guard
# installs once and runs against every project. A lane may also name an absolute
# path — the matching rule lives in agent-team-lane-paths.sh, shared with the
# dispatch guard, and its header carries why.
#
# Hook JSON on stdin. Exit 0 = allow. Exit 2 = block (stderr goes to the agent).
# Fail-closed: a policed role whose target cannot be positively confirmed inside
# its lane is refused, never allowed by default.
set -u

# shellcheck source=/dev/null
[ -r "$(dirname "$0")/agent-team-guard-log.sh" ] && . "$(dirname "$0")/agent-team-guard-log.sh"
command -v guard_log >/dev/null 2>&1 || guard_log() { :; }

ROLE="${1:-}"
readonly GUARD_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly LANES_FILE="$GUARD_DIR/agent-team-lanes.json"
# Built-in fallback, used only when config cannot be read. Same shape as the
# config: <role>=<colon-separated lanes>. It must mirror agent-team-lanes.json —
# a missing config file falls back to these, and a fallback that has forgotten a
# lane re-creates the very refusal the lane was added to prevent.
readonly DEFAULT_LANES="scribe=docs:plans:doc-inventory:~/.claude/projects/*/memory
architect=plans:docs:skills:agents
test-author=tests"

[ -n "$ROLE" ] || exit 0

# The matching rule is shared with the dispatch guard so that a path outside every
# lane here is a path with no owner there. Its absence is a broken install, and a
# policed role whose lane cannot be evaluated is refused rather than let through.
if [ -r "$GUARD_DIR/agent-team-lane-paths.sh" ]; then
  # shellcheck source=/dev/null
  . "$GUARD_DIR/agent-team-lane-paths.sh"
fi
if ! command -v lane_covers >/dev/null 2>&1; then
  case "$ROLE" in
    scribe|architect|test-author)
      guard_log lane "$ROLE" block "lane path rules missing"
      printf 'agent-team lane guard: agent-team-lane-paths.sh is missing beside this guard, so no lane can be evaluated — the install is incomplete. Blocking rather than failing open; re-run: bash install.sh\n' >&2
      exit 2 ;;
    *) exit 0 ;;
  esac
fi

lane_spec() { # -> colon-separated lanes for $ROLE, empty when unpoliced
  local from_config
  from_config="$(lane_role_spec "$ROLE" "$REPO_ROOT" "$LANES_FILE")"
  [ -n "$from_config" ] && { printf '%s' "$from_config"; return 0; }
  printf '%s\n' "$DEFAULT_LANES" \
    | sed -n "s/^${ROLE}=//p" | head -n1
}

INPUT="$(cat)"
if ! command -v jq >/dev/null 2>&1; then
  # Without jq the payload cannot be parsed. Only policed roles are affected, and
  # for them an unverifiable write is a block.
  case "$ROLE" in
    scribe|architect|test-author)
      guard_log lane "$ROLE" block "jq unavailable"
      printf 'agent-team lane guard: jq is not available, so this write cannot be confirmed inside the %s lane. Blocking rather than failing open.\n' "$ROLE" >&2
      exit 2 ;;
    *) exit 0 ;;
  esac
fi

PARSED="$(printf '%s' "$INPUT" | jq -c '.' 2>/dev/null)"
if [ -z "$PARSED" ]; then
  case "$ROLE" in
    scribe|architect|test-author)
      guard_log lane "$ROLE" block "invalid payload"
      printf 'agent-team lane guard: stdin was not valid JSON, so this write cannot be confirmed inside the %s lane. Blocking rather than failing open.\n' "$ROLE" >&2
      exit 2 ;;
    *) exit 0 ;;
  esac
fi

TOOL="$(printf '%s' "$PARSED" | jq -r '.tool_name // empty')"
case "$TOOL" in
  Write|Edit|NotebookEdit) ;;
  *) exit 0 ;;
esac

CWD="$(printf '%s' "$PARSED" | jq -r '.cwd // empty')"
[ -n "$CWD" ] || CWD="$PWD"

# The target is read, and the root and the lanes settled, in that order: the root
# is derived from the target below, and lane_spec reads the root when it looks for
# a project override.
TARGET_RAW="$(printf '%s' "$PARSED" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
if [ -z "$TARGET_RAW" ]; then
  guard_log lane "$ROLE" block "no file path in $TOOL"
  printf 'agent-team lane guard: a %s call carried no file path, so it cannot be confirmed inside the %s lane. Blocking rather than failing open.\n' "$TOOL" "$ROLE" >&2
  exit 2
fi

# Textual normalization FIRST: resolve "." and ".." by segment, so a path whose
# intermediate directory does not exist cannot survive as traversal. Doing this
# only by walking existing ancestors is not enough — `<lane>/nope/../../src/x`
# has a missing middle, the ancestor walk cannot resolve it, and the raw string
# still starts with the lane prefix. That is a lane bypass, so it is closed here
# before any comparison happens.
normalize_abs() { # $1 raw -> absolute path with no . or .. segments
  local p="$1" out="" seg old
  case "$p" in
    /*) ;;
    *) p="$CWD/$p" ;;
  esac
  old="$IFS"; IFS='/'
  for seg in $p; do
    IFS="$old"
    case "$seg" in
      ''|'.') ;;
      '..') out="${out%/*}" ;;
      *) out="$out/$seg" ;;
    esac
    IFS='/'
  done
  IFS="$old"
  printf '%s' "${out:-/}"
}

# Absolute, traversal-resolved, symlink-resolved form of a path that need not
# exist yet.
canonical_path() { # $1 raw
  local raw head tail_part parent
  raw="$(normalize_abs "$1")"
  head="$raw"; tail_part=""
  while [ -n "$head" ] && [ ! -d "$head" ]; do
    tail_part="$(basename "$head")${tail_part:+/$tail_part}"
    parent="$(dirname "$head")"
    [ "$parent" = "$head" ] && break
    head="$parent"
  done
  if [ -d "$head" ]; then
    head="$(cd "$head" 2>/dev/null && pwd -P)" || head="$raw"
  fi
  printf '%s' "${head%/}${tail_part:+/$tail_part}"
}

TARGET="$(canonical_path "$TARGET_RAW")"

# The repository root is resolved from the write TARGET, not from the session's
# working directory. A subagent's directory is fixed for its session's life and is
# always the parent checkout, so a directory-derived root measured a legitimate
# write inside a linked worktree — <worktree>/docs/... — as ".claude/..." from the
# parent root, outside every lane. Rooting on the target lands in the working tree
# actually being written, so <worktree>/docs satisfies the docs lane while
# <worktree>/src still does not. A target in no git working tree falls back to the
# directory-derived root, exactly as before.
target_repo_root() { # -> git top-level containing $TARGET, else the CWD-derived root
  local dir parent root
  dir="$TARGET"
  while [ -n "$dir" ] && [ ! -d "$dir" ]; do
    parent="$(dirname "$dir")"
    [ "$parent" = "$dir" ] && break
    dir="$parent"
  done
  if [ -d "$dir" ]; then
    root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$root" ] && { printf '%s' "$root"; return 0; }
  fi
  git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD"
}
REPO_ROOT="$(target_repo_root)"

LANES="$(lane_spec)"
# A role with no declared lane is not this guard's business.
[ -n "$LANES" ] || exit 0

ROOT="$(canonical_path "$REPO_ROOT")"

while IFS= read -r lane; do
  [ -n "$lane" ] || continue
  lane_covers "$TARGET" "$(lane_pattern "$lane" "$ROOT")" && exit 0
done <<EOF
$(printf '%s' "$LANES" | tr ':' '\n')
EOF

REL="$TARGET"
INSIDE_REPO=0
case "$REL" in "$ROOT"/*) REL="${REL#"$ROOT"/}"; INSIDE_REPO=1 ;; esac
guard_log lane "$ROLE" block "$REL"
if [ "$INSIDE_REPO" -eq 1 ]; then
  printf 'agent-team lane guard: this %s targets %s, outside the %s lane (%s under %s). That path belongs to another role — a document is the scribe'"'"'s, a plan or a skill is the architect'"'"'s, a test is the test-author'"'"'s, and source is the builder'"'"'s. Return the work to the orchestrator naming the file and what it needs; do not route around the lane by writing through a shell.\nReport the refusal in the typed form, on its own line, so the re-route is checked mechanically rather than re-interpreted:\n  WORKFORCE_REFUSAL: out-of-lane | %s\n' \
    "$TOOL" "$TARGET" "$ROLE" "$(printf '%s' "$LANES" | tr ':' ' ')" "$ROOT" "$REL" >&2
else
  # Outside the working tree entirely, so "another role owns it" may be false:
  # only a lane that names an absolute path reaches out here, and if none does,
  # no role can write this at all. Saying so is what stops the orchestrator
  # shopping the path around every specialist in turn.
  printf 'agent-team lane guard: this %s targets %s, which is outside this project'"'"'s working tree (%s) and outside the %s lane (%s). Lanes may name absolute paths, so if this path is genuinely this role'"'"'s, it belongs in the lane configuration (hooks/agent-team-lanes.json, or role_lanes in the project'"'"'s .workforce/project.json) rather than in a re-route — no other specialist has a wider lane out here, and the builder'"'"'s writes are confined to its own worktree. Report this to the orchestrator as a lane-configuration gap and stop.\nReport the refusal in the typed form, on its own line, so the re-route is checked mechanically rather than re-interpreted:\n  WORKFORCE_REFUSAL: out-of-lane | %s\n' \
    "$TOOL" "$TARGET" "$ROOT" "$ROLE" "$(printf '%s' "$LANES" | tr ':' ' ')" "$REL" >&2
fi
exit 2
