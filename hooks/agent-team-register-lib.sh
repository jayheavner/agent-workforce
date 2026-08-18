#!/usr/bin/env bash
# hooks/agent-team-register-lib.sh — derived names, liveness, safe rewrites, and the
# debris sweep for the work register.
#
# The register (agent-team-register.sh) holds the claim decisions; this file holds
# everything those decisions are computed FROM: where a timecard lives, which
# process a claim belongs to, whether that process is still the one it was, and how
# a card is rewritten without destroying a field this build does not know about.
# It was split out when the register outgrew the project's file-size discipline;
# sourcing agent-team-register.sh still defines every half, so no caller changes.
# The third half is agent-team-register-writer.sh: the atomic take and the writer
# slot, which is everything decided by contention rather than by reading state.
#
# Sourcing defines functions only; this file has no side effects and no CLI.
#
# Exit codes shared with the register: 1 no such card, 4 no session process,
# 5 register unusable, 6 bad slug.

REGISTER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTER_CONFIG_FILE="$REGISTER_LIB_DIR/agent-team-register.json"

# Commands that are never a session: the walk up the ancestry skips them.
REGISTER_SHELL_SET=" sh bash dash zsh ksh csh tcsh fish env timeout nice sudo ps "

# The integer beside this script, or the default when the config file is missing,
# unreadable, or does not hold an integer for that key.
register_config_int() { # $1 key $2 default
  local v=""
  if [ -r "$REGISTER_CONFIG_FILE" ]; then
    v="$(jq -r --arg k "$1" '.[$k] // empty' "$REGISTER_CONFIG_FILE" 2>/dev/null)"
  fi
  case "$v" in
    '' | *[!0-9]*) printf '%s' "$2" ;;
    *) printf '%s' "$v" ;;
  esac
}

# The register lives on the machine, not in a checkout, so a claim survives every
# worktree it describes. Tests point AGENT_TEAM_REGISTER_DIR at their own fixture.
register_root() {
  printf '%s' "${AGENT_TEAM_REGISTER_DIR:-$HOME/.claude/state/agent-workforce-register}"
}

# The MAIN checkout for a directory: when the top level is itself a linked
# worktree, the answer is the checkout that owns it, so every participant in a
# change resolves the same project whether it runs in the shared checkout or in
# the change's own tree. Exit 5 when the directory is in no repository.
register_project_root() { # $1 dir
  local top line
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 5
  [ -n "$top" ] || return 5
  if [ -f "$top/.git" ]; then
    line="$(head -n 1 "$top/.git" 2>/dev/null)"
    if [[ $line =~ ^gitdir:\ (.*)/\.git/worktrees/[^/]+$ ]]; then
      top="${BASH_REMATCH[1]}"
    fi
  fi
  [ -d "$top" ] || return 5
  (cd "$top" && pwd -P)
}

# Twelve hex characters of the project path's SHA-256: what keeps two unrelated
# projects both claiming `fix-typo` from colliding in one machine-scoped register.
register_project_key() { # $1 project-root
  local h
  if command -v shasum >/dev/null 2>&1; then
    h="$(printf '%s' "$1" | shasum -a 256 | awk '{print $1}')"
  elif command -v sha256sum >/dev/null 2>&1; then
    h="$(printf '%s' "$1" | sha256sum | awk '{print $1}')"
  else
    printf 'register: neither shasum nor sha256sum is available, so no project key can be derived\n' >&2
    return 5
  fi
  printf '%s' "${h:0:12}"
}

register_card_path() { # $1 project-root $2 slug
  local key
  key="$(register_project_key "$1")" || return 5
  printf '%s/%s/%s.json' "$(register_root)" "$key" "$2"
}

# Decision 10: the workspace path and its ref are DERIVED from the slug by every
# participant, never passed between them.
register_worktree_path() { # $1 project-root $2 slug
  printf '%s/.claude/worktrees/%s' "$1" "$2"
}

register_ref_name() { # $1 slug — the short ref; the full ref is refs/heads/<this>
  printf 'change/%s' "$1"
}

# A slug can never contain a path separator or `..`, so no card path and no
# worktree path derived from one can escape its directory — and the ref name
# derived from it has to be one git will accept, or this validator says yes and
# `worktree add` then says no in git's own words. A trailing `.` and a `.lock`
# suffix are the complete residue: every other rule `git check-ref-format`
# enforces on one path component — a leading `.`, a path separator, `@{`, a bare
# `@`, a backslash, whitespace, and `~ ^ : ? * [` — is already impossible under
# the character class below. Kept as pure shell rather than shelling out to git,
# because this is called on paths where no repository has been resolved yet.
register_valid_slug() { # $1 slug
  case "$1" in *..* | *. | *.lock) return 6 ;; esac
  [[ $1 =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || return 6
}

register_is_shell() { # $1 command basename
  case "$REGISTER_SHELL_SET" in *" $1 "*) return 0 ;; esac
  return 1
}

# The session's long-lived harness process, found by walking up from $PPID and
# skipping shells and wrappers; the first non-shell ancestor is the answer, and if
# the walk reaches pid 1 without one, the last ancestor before pid 1 is. Prints
# `<pid><tab><lstart string>`; exit 4 when there is no ancestor at all.
#
# This is what liveness rests on: the hook process itself exits seconds after a
# dispatch is allowed, so recording IT would make every claim look dead. The start
# string is `ps -p <pid> -o lstart=` verbatim — it contains spaces, is stored as a
# string, and is compared unprocessed on both sides.
register_session_process() {
  local pid="${PPID:-}" comm base parent last=""
  [ -n "$pid" ] || return 4
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; do
    comm="$(ps -p "$pid" -o comm= 2>/dev/null)"
    [ -n "$comm" ] || break
    base="${comm##*/}"
    base="${base#-}"
    if ! register_is_shell "$base"; then
      printf '%s\t%s' "$pid" "$(ps -p "$pid" -o lstart=)"
      return 0
    fi
    last="$pid"
    parent="$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d '[:space:]')"
    [ -n "$parent" ] || break
    pid="$parent"
  done
  [ -n "$last" ] || return 4
  printf '%s\t%s' "$last" "$(ps -p "$last" -o lstart=)"
}

# Both halves are required. Without the start string a recycled pid reports a
# stale claim as live and holds a slug indefinitely; the start-time comparison also
# needs no permission, which is why it is the second half rather than the only one.
# Noted limit on a shared machine: `kill -0` fails with EPERM for a live process
# owned by another user, which reads here as dead.
register_alive() { # $1 pid $2 start-string
  [ -n "${1:-}" ] || return 1
  kill -0 "$1" 2>/dev/null || return 1
  [ "$(ps -p "$1" -o lstart= 2>/dev/null)" = "${2:-}" ]
}

# Mode 700: the register names sessions, processes, and paths, and nothing else on
# the machine has any business reading it.
register_ensure_dir() { # $1 dir
  [ -d "$1" ] && return 0
  if mkdir -p "$1" 2>/dev/null; then
    chmod 700 "$(register_root)" 2>/dev/null
    chmod 700 "$1" 2>/dev/null
    return 0
  fi
  [ -d "$1" ] && return 0   # lost a benign race with another claimant
  printf 'register: the register directory %s does not exist and cannot be created. Repair: mkdir -p %s\n' \
    "$1" "$1" >&2
  return 5
}

# How many names a file has: 2 while a pin of ours stands beside a path that still
# exists, 1 once that path is gone. BSD `stat` first, then GNU; an unusable answer
# is empty, and callers treat that as "cannot tell" rather than as a verdict.
register_link_count() { # $1 path
  stat -f %l "$1" 2>/dev/null || stat -c %h "$1" 2>/dev/null
}

# Crash debris: a merged rewrite's temp file (`<card>.rewrite.<pid>`), a take's pin
# (`<card>.pin.<pid>`), a displacer's pin (`<slot-file>.stale.<pid>`), and an
# abandoned take token. None of them can ever be read as a timecard — no card glob
# matches them — but nothing swept them either, so a crash between the jq and the mv
# of a rewrite left one behind forever. A file whose trailing pid is gone, and a
# token whose taker is gone, have no owner that could still be writing them.
#
# Noted limit, deliberately left as it is: a trailing pid is checked with `kill -0`
# alone, without the process-start-time half that register_alive uses, because the
# file name carries a pid and nothing else. A RECYCLED pid therefore reads as the
# original owner and its debris survives this sweep. That error is in the safe
# direction — debris is kept, never a live writer's file removed — and the next
# sweep after the recycled pid exits collects it.
#
# It lives in this library rather than beside the writer slot's exclusive take, though
# every reap runs it last: what authorises a sweep is LIVENESS — the trailing pid has
# no process behind it — which is a fact one reader decides alone, not a fact two
# processes contend for. That is this file's half of the split.
register_sweep_debris() { # $1 dir
  local f pid
  [ -d "$1" ] || return 0
  for f in "$1"/*.rewrite.* "$1"/*.pin.* "$1"/*.stale.*; do
    [ -f "$f" ] || continue
    pid="${f##*.}"
    case "$pid" in '' | *[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null && continue
    rm -f "$f" && printf 'swept %s abandoned-rewrite\n' "$(basename "$f")"
  done
  for f in "$1"/.take.*; do
    [ -f "$f" ] || continue
    register_take_token_live "$f" && continue
    rm -f "$f" && printf 'swept %s abandoned-take-token\n' "$(basename "$f")"
  done
}

# Every rewrite goes through here: read the existing object, MERGE the changed
# fields, move a temp file in the same directory over the card. The card is never
# reconstructed from known fields, so a field written by a newer guard survives an
# older pinned one untouched.
#
# A `mv` is unconditional — it creates the destination when nothing is there — so a
# rewrite that started while the card existed and finished after another process
# REMOVED it would resurrect the path: a heartbeat racing a release would wedge a
# slug until its session died, and one racing a writer release would leave a ghost
# holder for up to the TTL. The bytes are therefore hard linked to a private name
# first, the merge reads THAT link, and the number of names the link still has is
# read immediately before the move: a count of 1 means the card path is gone, so the
# rewrite is abandoned instead of re-creating it. What remains is the residual window
# the whole design has: between that count and the `mv` there is no portable way to
# make "replace this path only if it still exists" one operation — unlink is by name,
# rename is unconditional, link is create-only, and the atomic-exchange system calls
# are not reachable from a shell. That window is microseconds wide and documented
# rather than hidden.
register_write_merged() { # $1 card $2 jq-program [jq args...]
  local card="$1" prog="$2" tmp pin links
  shift 2
  [ -f "$card" ] || return 1
  pin="$card.pin.$$"
  tmp="$card.rewrite.$$"
  rm -f "$pin"
  ln "$card" "$pin" 2>/dev/null || return 1
  if ! jq "$@" "$prog" "$pin" > "$tmp" 2>/dev/null; then
    rm -f "$tmp" "$pin"
    return 1
  fi
  links="$(register_link_count "$pin")"
  rm -f "$pin"
  # Only a positive count of 1 is evidence of a removal. A count above 2 is another
  # process pinning the same bytes, which is no reason to abandon anything, and an
  # unreadable count means `stat` could not answer — the rewrite proceeds, exactly
  # as it did before this check existed.
  if [ "$links" = "1" ]; then
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$card"
}

# An empty or unparseable timecard is DEAD, never a holder (decision 4).
register_card_json_ok() { # $1 card
  [ -s "$1" ] || return 1
  jq -e 'type == "object"' "$1" >/dev/null 2>&1
}

register_card_live() { # $1 card
  register_card_json_ok "$1" || return 1
  local pid start
  pid="$(jq -r '.pid // empty' "$1" 2>/dev/null)"
  start="$(jq -r '.pid_start // empty' "$1" 2>/dev/null)"
  register_alive "$pid" "$start"
}

# Decision 5's two-branch membership test. Prints which branch matched:
#   pid        — the recorded session process is this one. A subagent's payload id
#                may differ from its parent session's, and the harness process is
#                the same for both, so this branch carries that case.
#   session-id — the recorded session id is this one. A resumed session keeps its
#                id and gets a NEW process, so this branch is what lets it adopt
#                its own pre-resume claim.
# Neither branch can match a foreign session: ids are unique per session, and a
# live pid with its start time belongs to exactly one process.
register_card_member() { # $1 card $2 pid $3 pid-start $4 session-id
  register_card_json_ok "$1" || return 1
  local cpid cstart csess
  cpid="$(jq -r '.pid // empty' "$1" 2>/dev/null)"
  cstart="$(jq -r '.pid_start // empty' "$1" 2>/dev/null)"
  csess="$(jq -r '.session // empty' "$1" 2>/dev/null)"
  if [ -n "$cpid" ] && [ "$cpid" = "$2" ] && [ "$cstart" = "$3" ]; then
    printf 'pid\n'
    return 0
  fi
  if [ -n "$csess" ] && [ "$csess" = "$4" ]; then
    printf 'session-id\n'
    return 0
  fi
  return 1
}

# Timecard schema version 1, exactly as the plan states it.
register_new_card_json() { # $1 project $2 key $3 slug $4 session $5 pid $6 start
  local base_ref base_sha
  base_ref="$(git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null)"
  base_sha="$(git -C "$1" rev-parse HEAD 2>/dev/null)"
  jq -cn --arg slug "$3" --arg proj "$1" --arg key "$2" --arg sess "$4" \
    --argjson pid "$5" --arg start "$6" \
    --arg wt "$(register_worktree_path "$1" "$3")" \
    --arg ref "refs/heads/$(register_ref_name "$3")" \
    --arg base_ref "$base_ref" --arg base_sha "$base_sha" \
    --arg opened "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson hb "$(date +%s)" \
    '{v:1,slug:$slug,project:$proj,project_key:$key,session:$sess,pid:$pid,
      pid_start:$start,worktree:$wt,ref:$ref,base_ref:$base_ref,base_sha:$base_sha,
      state:"claiming",opened:$opened,heartbeat:$hb,writer:null}'
}

# The path of an EXISTING card: exit 1 when there is none, 5 when the project or
# the register cannot be resolved, 6 when the slug is illegal.
register_resolve_card() { # $1 project-dir $2 slug
  register_valid_slug "$2" || return 6
  local proj key card
  proj="$(register_project_root "$1")" || return 5
  key="$(register_project_key "$proj")" || return 5
  card="$(register_root)/$key/$2.json"
  [ -f "$card" ] || return 1
  printf '%s' "$card"
}
