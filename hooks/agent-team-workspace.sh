#!/usr/bin/env bash
# hooks/agent-team-workspace.sh — one place where a change's worktree is created,
# adopted, integrated, and removed.
#
# This is the ONLY component in the workspace-isolation design that runs a mutating
# git command, and that is the point: no agent runs `worktree add` or a merge
# against the shared checkout itself. `ensure` is called by the dispatch guard as a
# side effect of a `CHANGE: <slug>` declaration — no agent invokes it directly.
# `integrate` and `remove` are called by one explicit command the executor is
# dispatched to run, never by a Stop hook, because a mid-task pause that integrated
# unfinished work and deleted a live workspace is the failure that shape prevents.
#
# The path and the ref are DERIVED from the slug (decision 10), never passed:
# <project-root>/.claude/worktrees/<slug> at refs/heads/change/<slug>.
#
# Exit codes: 0 ok, 7 workspace unusable, 8 not integrable. Codes 1/3/4/5/6 come
# from the register and are passed through untouched.
#
# Sourcing this file defines functions only. Executing it dispatches `ensure`,
# `integrate`, and `remove`.
set -u

WORKSPACE_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$WORKSPACE_SELF_DIR/agent-team-register.sh" ]; then
  # The register's own SOURCE STATUS is the answer, not just its presence: when one
  # of its libraries is missing it returns non-zero without defining a single
  # function, and continuing from there means every command fails later on a missing
  # function — the wrong message, the wrong exit code, and the install-incomplete
  # diagnosis printed and thrown away.
  # shellcheck source=hooks/agent-team-register.sh
  . "$WORKSPACE_SELF_DIR/agent-team-register.sh" || { return 7 2>/dev/null || exit 7; }
else
  printf 'workspace: agent-team-register.sh is missing beside this script, so no change can be resolved — the install is incomplete. Re-run: bash install.sh\n' >&2
  return 7 2>/dev/null || exit 7
fi

# Is this exact path registered as a worktree, and at which ref? Prints the ref
# (`refs/heads/...` or `detached`) and exits 0 when the path is listed at all.
#
# The path is handed to awk through the ENVIRONMENT, not through `-v`: awk expands
# backslash escapes in a `-v` assignment, so a path containing one would be compared
# against a string it never equals.
workspace_registered_ref() { # $1 project-root $2 path
  git -C "$1" worktree list --porcelain 2>/dev/null \
    | WORKSPACE_AWK_PATH="worktree $2" awk '
        BEGIN { p = ENVIRON["WORKSPACE_AWK_PATH"] }
        $0 == p { seen = 1; ref = "detached"; next }
        seen && $1 == "branch" { ref = $2; exit }
        seen && $0 == "" { exit }
        END { if (seen) { print ref; exit 0 } ; exit 1 }'
}

# Create or adopt the change's worktree. Adoption is what makes a re-claim after a
# reap succeed against the tree a dead session left behind, rather than fighting
# over it.
workspace_ensure() { # $1 project-root $2 slug $3 base-ref
  register_valid_slug "$2" || {
    printf 'workspace: "%s" is not a legal change slug, so no worktree path can be derived from it\n' "$2" >&2
    return 6
  }
  # An un-ignored worktree directory turns every change into dirt in the shared
  # checkout, so this is refused before anything is created.
  if ! git -C "$1" check-ignore -q .claude/worktrees 2>/dev/null; then
    printf 'workspace: .claude/worktrees is not ignored in %s, so a change worktree would show up as untracked dirt in the shared checkout. Repair: add the line ".claude/worktrees/" to %s/.gitignore\n' \
      "$1" "$1" >&2
    return 7
  fi
  local path ref short listed
  path="$(register_worktree_path "$1" "$2")"
  short="$(register_ref_name "$2")"
  ref="refs/heads/$short"
  listed="$(workspace_registered_ref "$1" "$path")"
  # A registration whose directory is gone is stale: prune it and look again.
  if [ -n "$listed" ] && [ ! -d "$path" ]; then
    git -C "$1" worktree prune >/dev/null 2>&1
    listed="$(workspace_registered_ref "$1" "$path")"
  fi
  if [ -n "$listed" ] && [ -d "$path" ]; then
    if [ "$listed" = "$ref" ]; then
      printf '%s\n' "$path"      # adopt: touch nothing
      return 0
    fi
    printf 'workspace: %s is already registered as a worktree at %s, not at %s, so this change cannot use it. Repair: git -C %s worktree remove %s\n' \
      "$path" "$listed" "$ref" "$1" "$path" >&2
    return 7
  fi
  # On disk but unregistered: one prune, then it must be gone or it is debris.
  if [ -d "$path" ]; then
    git -C "$1" worktree prune >/dev/null 2>&1
    listed="$(workspace_registered_ref "$1" "$path")"
    if [ -z "$listed" ] && [ -d "$path" ]; then
      printf 'workspace: %s exists on disk but git does not know it as a worktree, so this change cannot use it. Repair: remove or rename %s, then dispatch again\n' \
        "$path" "$path" >&2
      return 7
    fi
    if [ -n "$listed" ] && [ "$listed" = "$ref" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  fi
  local err
  if git -C "$1" show-ref --verify --quiet "$ref"; then
    # The ref survived its tree: attach to it rather than starting over, so work
    # committed before a crash is not stranded.
    err="$(git -C "$1" worktree add "$path" "$short" 2>&1)" || {
      printf 'workspace: could not attach a worktree at %s to the existing ref %s: %s\n' \
        "$path" "$ref" "$err" >&2
      return 7
    }
  else
    err="$(git -C "$1" worktree add "$path" -b "$short" "$3" 2>&1)" || {
      printf 'workspace: could not create the worktree %s at %s from %s: %s\n' \
        "$path" "$ref" "$3" "$err" >&2
      return 7
    }
  fi
  printf '%s\n' "$path"
}

# Merge the change into the integration ref, then take the workspace down and
# release the claim — but only when every precondition holds, and only ever as a
# whole. A conflicted merge is aborted and leaves the tree, the ref, and the
# timecard exactly as they were.
workspace_integrate() { # $1 project-root $2 slug $3 integration-ref [$4 session-id]
  local card path short head dirty err
  card="$(register_resolve_card "$1" "$2")" || {
    printf 'workspace: there is no timecard for %s in %s, so there is no claim to integrate. Repair: dispatch the work with "CHANGE: %s" first\n' \
      "$2" "$1" "$2" >&2
    return 8
  }
  if ! register_mine "$1" "$2" "${4:-}" >/dev/null; then
    printf 'workspace: the timecard for %s is held by session %s, so this session may not integrate it\n' \
      "$2" "$(jq -r '.session // "unknown"' "$card")" >&2
    return 8
  fi
  path="$(register_worktree_path "$1" "$2")"
  short="$(register_ref_name "$2")"
  # The tree has to be there before its cleanliness can mean anything: a card whose
  # tree was deleted by hand would otherwise pass an empty dirty check, merge, and
  # only then fail at worktree removal — with the merge already done.
  if [ ! -d "$path" ]; then
    printf 'workspace: the change worktree %s does not exist, so %s cannot be integrated from it. Repair: dispatch the change again — the tree is re-attached to the surviving ref %s, then integrate\n' \
      "$path" "$2" "refs/heads/$short" >&2
    return 8
  fi
  dirty="$(git -C "$path" status --porcelain 2>/dev/null)"
  if [ -n "$dirty" ]; then
    printf 'workspace: the change worktree %s has uncommitted work, so integrating it would lose or ship it unreviewed:\n%s\n' \
      "$path" "$dirty" >&2
    return 8
  fi
  head="$(git -C "$1" symbolic-ref --short HEAD 2>/dev/null)"
  if [ "$head" != "$3" ]; then
    printf 'workspace: %s is on %s, not on the integration ref %s, so the merge would land somewhere unintended\n' \
      "$1" "${head:-a detached HEAD}" "$3" >&2
    return 8
  fi
  dirty="$(git -C "$1" status --porcelain 2>/dev/null)"
  if [ -n "$dirty" ]; then
    printf 'workspace: %s has uncommitted work, so a merge into it would mix two changes:\n%s\n' \
      "$1" "$dirty" >&2
    return 8
  fi
  if ! err="$(git -C "$1" merge --no-ff --no-edit "$short" 2>&1)"; then
    git -C "$1" merge --abort >/dev/null 2>&1
    printf 'workspace: merging %s into %s did not succeed, so it was aborted and nothing changed: %s\n' \
      "$short" "$3" "$err" >&2
    return 8
  fi
  if ! err="$(git -C "$1" worktree remove "$path" 2>&1)"; then
    printf 'workspace: %s merged into %s, but its worktree %s could not be removed: %s\n' \
      "$short" "$3" "$path" "$err" >&2
    return 8
  fi
  git -C "$1" update-ref -d "refs/heads/$short" || return 8
  # The whole claim is coming down, and the checks above have already established
  # that it is this caller's own, so the writer slot goes with it whoever holds it —
  # unconditional by design, since no change is left for a holder to write in. The
  # slot-scoped path is `writer-release`, which refuses a slot it does not hold.
  register_writer_teardown "$1" "$2" >/dev/null 2>&1
  # The session id this call was made with is passed through: without it, release
  # can only establish membership by the process arm, so an executor holding a
  # payload id different from its own process would be refused its own claim.
  register_release "$1" "$2" "${4:-}" || return 8
}

# Take a change's workspace down without integrating it — allowed only once its
# commits are already reachable from HEAD, so nothing is ever destroyed unreviewed,
# and only when the claim is this session's own.
#
# Both checks come BEFORE anything is destroyed. A removal that deleted the ref and
# the tree and only then failed to release a foreign card would report success and
# leave a live claim pointing at nothing.
workspace_remove() { # $1 project-root $2 slug [$3 session-id]
  register_valid_slug "$2" || {
    printf 'workspace: "%s" is not a legal change slug, so no worktree path can be derived from it\n' "$2" >&2
    return 6
  }
  local path short unmerged err card rc
  short="$(register_ref_name "$2")"
  path="$(register_worktree_path "$1" "$2")"
  card="$(register_resolve_card "$1" "$2")" || card=""
  if [ -n "$card" ] && ! register_mine "$1" "$2" "${3:-}" >/dev/null; then
    printf 'workspace: the timecard for %s is held by session %s, so this session may not remove it\n' \
      "$2" "$(jq -r '.session // "unknown"' "$card")" >&2
    return 8
  fi
  if ! git -C "$1" show-ref --verify --quiet "refs/heads/$short"; then
    printf 'workspace: there is no ref refs/heads/%s in %s, so there is no change workspace to remove\n' \
      "$short" "$1" >&2
    return 8
  fi
  if ! git -C "$1" merge-base --is-ancestor "$short" HEAD 2>/dev/null; then
    unmerged="$(git -C "$1" log --oneline "HEAD..$short" 2>/dev/null | tr '\n' ' ')"
    printf 'workspace: %s still holds commits that are not in HEAD, so removing it would lose them: %s\n' \
      "$short" "$unmerged" >&2
    return 8
  fi
  if [ -d "$path" ]; then
    if ! err="$(git -C "$1" worktree remove "$path" 2>&1)"; then
      printf 'workspace: could not remove the worktree %s: %s\n' "$path" "$err" >&2
      return 8
    fi
  fi
  git -C "$1" update-ref -d "refs/heads/$short" || return 8
  # The release verdict is the caller's business, not something to swallow: a claim
  # that survives its workspace is a slug held by nothing.
  [ -n "$card" ] || return 0
  register_release "$1" "$2" "${3:-}" || {
    rc=$?
    [ "$rc" -eq 1 ] && return 0     # already released: the slug is free, as intended
    printf 'workspace: %s was taken down but its timecard could not be released, so the slug is still held\n' \
      "$2" >&2
    return "$rc"
  }
}

workspace_main() {
  local cmd="${1:-}"
  [ "$#" -gt 0 ] && shift
  case "$cmd" in
    ensure) workspace_ensure "$@" ;;
    integrate) workspace_integrate "$@" ;;
    remove) workspace_remove "$@" ;;
    *)
      printf 'workspace: unknown subcommand "%s". Known: ensure integrate remove\n' "$cmd" >&2
      return 2
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  workspace_main "$@"
fi
