#!/usr/bin/env bash
# agent-team-lane-paths.sh — the one rule for "which paths does a lane cover",
# sourced by the guard that ENFORCES lanes (agent-team-lane-guard.sh) and by the
# guard that ROUTES by them (agent-team-dispatch-guard.sh). Two readers of one
# rule is what keeps a path from being outside every lane in the first guard and
# owned by a role in the second — which is exactly the loop this file was written
# to remove.
#
# The loop, 2026-08-04. Every lane was a directory inside a checkout, so a path
# that lives nowhere near one — the agent memory at
# ~/.claude/projects/<project>/memory — was outside every lane by construction.
# The lane guard refused it for the scribe, correctly by its own rule. The
# dispatch guard's "nothing claims it, so it is source, so it is the builder's"
# fallback then named the one role that is confined to a git worktree. The
# worktree guard refused it there, also correctly. Three guards, each right alone,
# and no role left that could write the file. The only exit was the human's
# override, for work nobody had any reason to object to.
#
# Two changes remove it. A lane may now name an absolute path, so a directory
# outside the repository can belong to a role. And a `*` in a lane matches exactly
# ONE path segment, so ~/.claude/projects/*/memory covers one project's memory
# directory without covering ~/.claude/projects itself — which holds the session
# transcripts these guards read to decide anything at all.
#
# A lane is one of:
#   docs                          repo-relative; joined to the working tree root
#   /absolute/path                filesystem-anchored
#   ~/relative/to/home            filesystem-anchored, $HOME expanded
#   ~/.claude/projects/*/memory   the same, with `*` matching one segment
#
# Sourced, not executed. Defines functions and nothing else.

# Absolute, symlink-resolved form of a path that need not exist yet: the deepest
# existing ancestor is resolved and the remainder re-appended. A lane and a write
# target must be compared in the same form or a symlinked ancestor makes an honest
# write look like it is outside its lane.
lane_paths_canonical() { # $1 absolute path
  local raw="$1" head tail_part parent
  head="$raw"
  tail_part=""
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

# A lane as one absolute pattern. Repo-relative lanes are joined to $2; `~` is
# expanded; and everything before the first wildcard is symlink-resolved, since a
# pattern cannot be resolved as a whole once it stops naming a real directory.
lane_pattern() { # $1 lane, $2 working tree root
  local lane="$1" root="$2" p head tail_part
  [ -n "$lane" ] || return 0
  case "$lane" in
    '~') p="$HOME" ;;
    '~/'*) p="$HOME/${lane#\~/}" ;;
    /*) p="$lane" ;;
    *) p="$root/$lane" ;;
  esac
  case "$p" in
    */) p="${p%/}" ;;
  esac
  case "$p" in
    *'*'*)
      head="${p%%\**}"
      tail_part="${p#"$head"}"
      head="${head%/}"
      printf '%s/%s' "$(lane_paths_canonical "$head")" "${tail_part#/}"
      ;;
    *) printf '%s' "$(lane_paths_canonical "$p")" ;;
  esac
}

# True when the target $1 is the lane $2 itself or lives underneath it. Compared
# segment by segment, so a `*` matches one segment and never a run of them: a lane
# of ~/.claude/projects/*/memory covers ~/.claude/projects/<one>/memory/file.md
# and does not cover ~/.claude/projects/<one>/session.jsonl, nor
# ~/.claude/projects/<one>/<deeper>/memory/file.md.
lane_covers() { # $1 canonical absolute target, $2 absolute lane pattern
  local target="$1" pattern="$2" t p pseg tseg
  [ -n "$target" ] && [ -n "$pattern" ] || return 1
  case "$target" in /*) ;; *) return 1 ;; esac
  case "$pattern" in /*) ;; *) return 1 ;; esac
  t="${target#/}"
  p="${pattern#/}"
  while [ -n "$p" ]; do
    if [ "${p%%/*}" = "$p" ]; then pseg="$p"; p=""; else pseg="${p%%/*}"; p="${p#*/}"; fi
    [ -n "$t" ] || return 1
    if [ "${t%%/*}" = "$t" ]; then tseg="$t"; t=""; else tseg="${t%%/*}"; t="${t#*/}"; fi
    [ "$pseg" = '*' ] || [ "$pseg" = "$tseg" ] || return 1
  done
  return 0
}

# The lanes in force for a role, colon-separated, empty when the role has none.
# The project's own declaration is read first and wins outright — a project that
# names a role's lanes REPLACES them rather than adding to them, because these
# directory names are one repository's conventions and the guards install once and
# run against every project.
lane_role_spec() { # $1 role, $2 working tree root, $3 shipped lanes file
  local role="$1" root="$2" file="$3" src spec
  command -v jq >/dev/null 2>&1 || return 0
  for src in "$root/.workforce/project.json" "$file"; do
    [ -f "$src" ] || continue
    spec="$(jq -r --arg r "$role" '
      (.role_lanes[$r]? // empty)
      | if type == "array" then map(tostring | sub("/+$";"")) | join(":") else empty end
    ' "$src" 2>/dev/null | head -n1)"
    [ -n "$spec" ] && { printf '%s' "$spec"; return 0; }
  done
  return 0
}

# Every role either config gives lanes to, the project's first, each named once.
lane_roles() { # $1 working tree root, $2 shipped lanes file
  local root="$1" file="$2"
  command -v jq >/dev/null 2>&1 || return 0
  {
    [ -f "$root/.workforce/project.json" ] &&
      jq -r '(.role_lanes // {}) | keys_unsorted[]' "$root/.workforce/project.json" 2>/dev/null
    [ -f "$file" ] &&
      jq -r '(.role_lanes // {}) | keys_unsorted[]' "$file" 2>/dev/null
  } | awk '!seen[$0]++'
}

# The role whose lane covers $1, or empty when no lane does. Empty is a real
# answer and must not be read as "the builder's": a path no lane claims may be
# source inside the repository, which IS the builder's, or it may be somewhere no
# role can write at all. Only the caller knows which, because only the caller
# knows where the repository ends.
lane_role_owner() { # $1 canonical absolute target, $2 working tree root, $3 lanes file
  local target="$1" root="$2" file="$3" role lane
  while IFS= read -r role; do
    [ -n "$role" ] || continue
    while IFS= read -r lane; do
      [ -n "$lane" ] || continue
      if lane_covers "$target" "$(lane_pattern "$lane" "$root")"; then
        printf '%s' "$role"
        return 0
      fi
    done <<EOF
$(lane_role_spec "$role" "$root" "$file" | tr ':' '\n')
EOF
  done <<EOF
$(lane_roles "$root" "$file")
EOF
  return 0
}
