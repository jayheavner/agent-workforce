#!/usr/bin/env bash
# agent-team-worktree-guard.sh <role> — enforces policy:workspace-isolation on
# the builder: it may only WRITE inside its own unique linked git worktree, and
# it may not finish unless it actually worked in one.
#
# Two events, one entrypoint (dispatched on hook_event_name):
#   PreToolUse(Write|Edit|NotebookEdit|Bash) — prevention. A write aimed at the
#     parent checkout, at another builder's worktree, or at anything that is not
#     the builder's own declared worktree is refused BEFORE it happens.
#   Stop|SubagentStop — the backstop. A builder cannot report completion unless
#     its declared worktree exists and is a registered linked worktree.
#
# The declared worktree is the `WORKTREE: <path>` line the orchestrator put in
# the dispatch prompt (the dispatch guard refuses a builder without one). This
# hook re-reads it from the subagent's own transcript, so the builder cannot
# widen its own boundary by editing anything at runtime.
#
# Reads are deliberately unrestricted: the plan, repository guidance, and
# CONTEXT.md all live in the parent checkout and the builder must read them.
# Only mutation is confined.
#
# Second rule, same event: the separately-authored acceptance suite is read-only
# to the builder even inside its own worktree. Whoever writes the code is never
# the last author of the bar it is judged against — builder.md has said so in
# prose since the checks-and-balances spec, and prose is what failed on
# 2026-08-03 when a single actor authored a change, its test, and its own
# verdict. The suite's location is configuration (agent-team-lanes.json beside
# this guard, overridable per project in .workforce/project.json) because it is
# not the same directory in every repository.
#
# Known limit, stated rather than hidden: for Bash the confinement is the
# effective working directory plus any explicit `git -C <path>`. The effective
# directory is the payload's working directory, unless the command opens by
# stepping into the declared worktree (`cd` or `pushd`), which is honored: a
# subagent's payload directory is its session's, fixed for the session's life and
# always the parent checkout, so without honoring that first step a builder could
# never enter its own worktree at all. A command that changes directory later,
# mid-command, and then writes is still not caught here — the Stop backstop and
# the reviewer's diff are the nets behind that case.
#
# Hook JSON on stdin. Exit 0 = allow. Exit 2 = block (stderr goes to the agent).
# Fail-closed: anything that leaves this guard unable to positively confirm the
# write lands in the builder's own worktree is a block, never a silent allow.
set -u

readonly POLICED_ROLES="builder"
readonly WORKTREE_MARKER_PREFIX="WORKTREE:"
# Shipped default for the read-only acceptance suite. Config that cannot be read
# falls back to this rather than to "no rule": a missing config file is a broken
# install, never permission to edit your own bar.
readonly DEFAULT_ACCEPTANCE_PATHS="tests/acceptance"
readonly LANES_FILE="$(cd "$(dirname "$0")" && pwd)/agent-team-lanes.json"
# shellcheck source=/dev/null
[ -r "$(dirname "$0")/agent-team-guard-log.sh" ] && . "$(dirname "$0")/agent-team-guard-log.sh"
command -v guard_log >/dev/null 2>&1 || guard_log() { :; }

ROLE="${1:-}"

# Roles other than the policed ones are none of this guard's business.
POLICED=0
for name in $POLICED_ROLES; do
  [ "$ROLE" = "$name" ] && POLICED=1 && break
done
[ "$POLICED" -eq 1 ] || exit 0

if ! command -v jq >/dev/null 2>&1; then
  printf 'agent-team worktree guard: jq is not available, so this guard cannot parse the payload. Blocking rather than failing open.\n' >&2
  exit 2
fi

INPUT="$(cat)"
PARSED="$(printf '%s' "$INPUT" | jq -c '.' 2>/dev/null)"
if [ -z "$PARSED" ]; then
  printf 'agent-team worktree guard: stdin was not valid JSON, so this action cannot be verified against policy:workspace-isolation. Blocking rather than failing open.\n' >&2
  exit 2
fi

EVENT="$(printf '%s' "$PARSED" | jq -r '.hook_event_name // empty')"
TOOL="$(printf '%s' "$PARSED" | jq -r '.tool_name // empty')"
CWD="$(printf '%s' "$PARSED" | jq -r '.cwd // empty')"
TRANSCRIPT="$(printf '%s' "$PARSED" | jq -r '.transcript_path // empty')"

# Absolute, symlink-resolved, trailing-slash-free form of a path that may not
# exist yet (the builder creates files as it goes). Resolves the deepest
# existing ancestor, then re-appends the remainder, so traversal like
# `<wt>/../../file` cannot masquerade as being inside the worktree.
normalize_abs() { # $1 raw -> absolute path with no . or .. segments
  local p="$1" out="" seg old
  case "$p" in
    /*) ;;
    *) p="${CWD:-$PWD}/$p" ;;
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

canonical_path() {
  local raw head tail_part
  # Traversal is resolved textually FIRST. Walking existing ancestors alone
  # cannot resolve `<wt>/nope/../../file`: the middle segment does not exist, so
  # the walk gives up and the raw string still carries the worktree prefix —
  # which path_within would then accept. That is a confinement bypass.
  raw="$(normalize_abs "$1")"
  head="$raw"
  tail_part=""
  while [ -n "$head" ] && [ ! -d "$head" ]; do
    tail_part="$(basename "$head")${tail_part:+/$tail_part}"
    local parent
    parent="$(dirname "$head")"
    [ "$parent" = "$head" ] && break
    head="$parent"
  done
  if [ -d "$head" ]; then
    head="$(cd "$head" 2>/dev/null && pwd -P)" || head="$raw"
  fi
  printf '%s' "${head%/}${tail_part:+/$tail_part}"
}

# True when $1 is $2 or lives underneath it.
path_within() { # $1 candidate $2 container
  case "$1" in
    "$2") return 0 ;;
    "$2"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# The directory a command opens by stepping into it: the argument of a leading
# `cd` or `pushd`, unquoted, or empty when the command does not begin that way.
# Only the FIRST statement counts — this guard does not simulate a shell, and a
# directory change buried later in a command is the known limit stated above.
leading_cd_target() { # $1 command -> path or empty
  local first rest target
  first="$(printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e '/^$/d' | head -n1)"
  case "$first" in
    cd[[:space:]]*) rest="${first#cd}" ;;
    pushd[[:space:]]*) rest="${first#pushd}" ;;
    *) return 0 ;;
  esac
  rest="${rest#"${rest%%[![:space:]]*}"}"
  case "$rest" in
    '"'*) rest="${rest#\"}"; target="${rest%%\"*}" ;;
    "'"*) rest="${rest#\'}"; target="${rest%%\'*}" ;;
    *) target="${rest%%[[:space:];&|]*}" ;;
  esac
  printf '%s' "$target"
}

# A linked worktree's .git is a FILE pointing at <main>/.git/worktrees/<name>;
# the main checkout's .git is a directory. That distinction is what makes a
# path "a worktree of its own" rather than the shared checkout.
is_linked_worktree() { # $1 path
  [ -f "$1/.git" ] || return 1
  head -n1 "$1/.git" 2>/dev/null | grep -Eq '^gitdir: .*/\.git/worktrees/[^/]+[[:space:]]*$'
}

# The main checkout behind a linked worktree: its .git file points at
# <main>/.git/worktrees/<name>, so the prefix before that is the main checkout.
main_checkout() { # $1 linked worktree
  local gitdir
  gitdir="$(head -n1 "$1/.git" 2>/dev/null | sed -e 's/^gitdir:[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$gitdir" in
    */.git/worktrees/*) printf '%s' "${gitdir%%/.git/worktrees/*}" ;;
    *) return 1 ;;
  esac
}

# Acceptance-suite paths relative to the worktree root, one per line. Resolution
# order: this project's declaration, then the shipped config, then the built-in
# default — so a repository whose suite is not tests/acceptance says so once in
# .workforce/project.json instead of losing the rule.
acceptance_paths() {
  local main="" override="" shipped=""
  if main="$(main_checkout "$DECLARED")" && [ -f "$main/.workforce/project.json" ]; then
    override="$(jq -r '.acceptance_suite_paths[]? // empty' "$main/.workforce/project.json" 2>/dev/null)"
  fi
  if [ -n "$override" ]; then
    printf '%s\n' "$override"
    return 0
  fi
  if [ -f "$LANES_FILE" ]; then
    shipped="$(jq -r '.acceptance_suite_paths[]? // empty' "$LANES_FILE" 2>/dev/null)"
    if [ -n "$shipped" ]; then
      printf '%s\n' "$shipped"
      return 0
    fi
  fi
  printf '%s\n' "$DEFAULT_ACCEPTANCE_PATHS"
}

# The worktree the dispatch assigned to this builder, read from its transcript.
declared_worktree() {
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || return 0
  jq -rs --arg marker "$WORKTREE_MARKER_PREFIX" '
    [ .[] | .. | strings
      | select(contains($marker))
      | [ splits("\n") ]
      | map(select(startswith($marker)))
      | .[]
      | ltrimstr($marker)
    ] | if length == 0 then empty else .[0] end
  ' "$TRANSCRIPT" 2>/dev/null \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's:/*$::' \
    | head -n1
}

DECLARED_RAW="$(declared_worktree)"
if [ -z "$DECLARED_RAW" ]; then
  printf 'agent-team worktree guard: this builder has no "%s <path>" line in its dispatch, so policy:workspace-isolation cannot be enforced and no write can be confirmed safe. The orchestrator must dispatch every builder with its own unique worktree path.\n' \
    "$WORKTREE_MARKER_PREFIX" >&2
  exit 2
fi
DECLARED="$(canonical_path "$DECLARED_RAW")"

if ! is_linked_worktree "$DECLARED"; then
  printf 'agent-team worktree guard: the declared worktree %s is not a registered linked git worktree, so this builder is not isolated from the shared checkout or from other builders. Create it first:\n  git -C <project> worktree add %s -b <task-branch>\n' \
    "$DECLARED" "$DECLARED" >&2
  exit 2
fi

case "$EVENT" in
  Stop|SubagentStop)
    # The declaration exists and names a real linked worktree — the isolation
    # the policy requires was in place for this dispatch.
    exit 0
    ;;
esac

# --- PreToolUse: confine mutation to $DECLARED.
refuse() { # $1 target $2 what
  printf 'agent-team worktree guard: %s targets %s, which is outside this builder'"'"'s worktree (%s). policy:workspace-isolation confines every write to your own worktree — never the parent checkout, never another builder'"'"'s tree. Re-run it inside %s, or report the mismatch as a plan defect if the work genuinely belongs elsewhere.\n' \
    "$2" "$1" "$DECLARED" "$DECLARED" >&2
  guard_log worktree "$ROLE" block "$1"
  exit 2
}

case "$TOOL" in
  Write|Edit|NotebookEdit)
    TARGET_RAW="$(printf '%s' "$PARSED" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
    if [ -z "$TARGET_RAW" ]; then
      printf 'agent-team worktree guard: a %s call carried no file path, so its target cannot be confined to %s. Blocking rather than failing open.\n' "$TOOL" "$DECLARED" >&2
      exit 2
    fi
    TARGET="$(canonical_path "$TARGET_RAW")"
    path_within "$TARGET" "$DECLARED" || refuse "$TARGET" "this $TOOL"

    # Inside the worktree, the acceptance suite is still not the builder's to write.
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      case "$rel" in /*) continue ;; esac
      if path_within "$TARGET" "$(canonical_path "$DECLARED/${rel%/}")"; then
        printf 'agent-team worktree guard: this %s targets %s, inside the separately-authored acceptance suite (%s). That suite is the bar this build is judged against, authored by an agent that never writes the code, and it is read-only to you — a test that looks wrong is a plan defect to report, never a file to edit. Make the suite pass, or report the defect.\n' \
          "$TOOL" "$TARGET" "$rel" >&2
        guard_log worktree "$ROLE" block "acceptance-suite: $rel"
        exit 2
      fi
    done <<EOF
$(acceptance_paths)
EOF
    ;;
  Bash)
    COMMAND="$(printf '%s' "$PARSED" | jq -r '.tool_input.command // empty')"
    if [ -z "$CWD" ]; then
      printf 'agent-team worktree guard: this Bash call carried no working directory, so it cannot be confined to %s. Blocking rather than failing open.\n' "$DECLARED" >&2
      exit 2
    fi
    RUN_DIR="$(canonical_path "$CWD")"
    # A subagent's payload directory is its session's — fixed for the session's
    # life and always the parent checkout — so judged by that alone every builder
    # command was refused, including the `cd` into its own worktree. When the
    # command's first statement steps into the declared worktree, that is where
    # the command actually runs, so that becomes the effective directory.
    # Anything else is judged exactly as before.
    CD_RAW="$(leading_cd_target "$COMMAND")"
    if [ -n "$CD_RAW" ]; then
      CD_TARGET="$(canonical_path "$CD_RAW")"
      path_within "$CD_TARGET" "$DECLARED" && RUN_DIR="$CD_TARGET"
    fi
    path_within "$RUN_DIR" "$DECLARED" || refuse "$RUN_DIR" "this shell command's working directory"

    # `git -C <path>` retargets Git itself; it must not leave the worktree.
    printf '%s\n' "$COMMAND" \
      | grep -Eo '(^|[[:space:]])git[[:space:]]+(-[^C[:space:]]+[[:space:]]+)*-C[[:space:]]+("[^"]+"|'"'"'[^'"'"']+'"'"'|[^[:space:];|&]+)' \
      | sed -E 's/.*-C[[:space:]]+//; s/^"//; s/"$//; s/^'"'"'//; s/'"'"'$//' \
      | while IFS= read -r gitdir; do
          [ -n "$gitdir" ] || continue
          resolved="$(canonical_path "$gitdir")"
          path_within "$resolved" "$DECLARED" || {
            printf 'agent-team worktree guard: this command runs `git -C %s`, outside this builder'"'"'s worktree (%s). policy:workspace-isolation forbids operating on the parent checkout or another builder'"'"'s tree. Drop the -C and run Git inside your own worktree.\n' \
              "$resolved" "$DECLARED" >&2
            exit 2
          }
        done
    # The subshell above cannot exit this script directly; propagate its status.
    # shellcheck disable=SC2181
    [ "$?" -eq 0 ] || exit 2
    ;;
esac

exit 0
