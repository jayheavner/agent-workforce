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
# installs once and runs against every project.
#
# Hook JSON on stdin. Exit 0 = allow. Exit 2 = block (stderr goes to the agent).
# Fail-closed: a policed role whose target cannot be positively confirmed inside
# its lane is refused, never allowed by default.
set -u

ROLE="${1:-}"
readonly LANES_FILE="$(cd "$(dirname "$0")" && pwd)/agent-team-lanes.json"
# Built-in fallback, used only when config cannot be read. Same shape as the
# config: <role>=<colon-separated repo-relative directories>.
readonly DEFAULT_LANES="scribe=docs:plans:doc-inventory
architect=plans:docs:skills:agents
test-author=tests"

[ -n "$ROLE" ] || exit 0

lane_spec() { # -> colon-separated dirs for $ROLE, empty when unpoliced
  local from_config=""
  if command -v jq >/dev/null 2>&1; then
    for src in "$REPO_ROOT/.workforce/project.json" "$LANES_FILE"; do
      [ -f "$src" ] || continue
      from_config="$(jq -r --arg r "$ROLE" '
        (.role_lanes[$r]? // empty)
        | if type == "array" then map(tostring | sub("^/+";"") | sub("/+$";"")) | join(":")
          else empty end
      ' "$src" 2>/dev/null | head -n1)"
      [ -n "$from_config" ] && { printf '%s' "$from_config"; return 0; }
    done
  fi
  printf '%s\n' "$DEFAULT_LANES" \
    | sed -n "s/^${ROLE}=//p" | head -n1
}

INPUT="$(cat)"
if ! command -v jq >/dev/null 2>&1; then
  # Without jq the payload cannot be parsed. Only policed roles are affected, and
  # for them an unverifiable write is a block.
  case "$ROLE" in
    scribe|architect|test-author)
      printf 'agent-team lane guard: jq is not available, so this write cannot be confirmed inside the %s lane. Blocking rather than failing open.\n' "$ROLE" >&2
      exit 2 ;;
    *) exit 0 ;;
  esac
fi

PARSED="$(printf '%s' "$INPUT" | jq -c '.' 2>/dev/null)"
if [ -z "$PARSED" ]; then
  case "$ROLE" in
    scribe|architect|test-author)
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
REPO_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")"

LANES="$(lane_spec)"
# A role with no declared lane is not this guard's business.
[ -n "$LANES" ] || exit 0

TARGET_RAW="$(printf '%s' "$PARSED" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
if [ -z "$TARGET_RAW" ]; then
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
ROOT="$(canonical_path "$REPO_ROOT")"

old_ifs="$IFS"; IFS=':'
for lane in $LANES; do
  IFS="$old_ifs"
  [ -n "$lane" ] || continue
  allowed="$(canonical_path "$ROOT/$lane")"
  case "$TARGET" in
    "$allowed"|"$allowed"/*) exit 0 ;;
  esac
  IFS=':'
done
IFS="$old_ifs"

REL="$TARGET"
case "$REL" in "$ROOT"/*) REL="${REL#"$ROOT"/}" ;; esac
printf 'agent-team lane guard: this %s targets %s, outside the %s lane (%s under %s). That path belongs to another role — a document is the scribe'"'"'s, a plan or a skill is the architect'"'"'s, a test is the test-author'"'"'s, and source is the builder'"'"'s. Return the work to the orchestrator naming the file and what it needs; do not route around the lane by writing through a shell.\nReport the refusal in the typed form, on its own line, so the re-route is checked mechanically rather than re-interpreted:\n  WORKFORCE_REFUSAL: out-of-lane | %s\n' \
  "$TOOL" "$TARGET" "$ROLE" "$(printf '%s' "$LANES" | tr ':' ' ')" "$ROOT" "$REL" >&2
exit 2
