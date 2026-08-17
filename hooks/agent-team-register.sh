#!/usr/bin/env bash
# hooks/agent-team-register.sh — the work register: one timecard per change.
#
# The unit of isolation is the CHANGE, not the agent. A change is owned by whoever
# holds its timecard: one small JSON file per claim, in a machine-scoped,
# per-project register directory, created with the filesystem's own atomic
# exclusive create. Two processes cannot both create one path, so exclusion needs
# no lock file, no append to a shared list, and no coordinator.
#
# Three rules the design rests on (plan decision 3):
#   * creation is `( set -o noclobber; printf ... > "$card" )` — the noclobber is
#     set HERE, never assumed from the caller, and never mktemp+mv, which would
#     clobber silently and destroy the exclusion this design rests on;
#   * a failed creation is NOT evidence of a holder — the path is re-read, and a
#     missing or unwritable register directory is exit 5 with its repair, never a
#     holder;
#   * every rewrite MERGES into the existing object (register_write_merged), so a
#     field written by a newer guard survives an older pinned one.
#
# Liveness is the session's long-lived harness process — its pid AND its start
# time — never the short-lived hook process that wrote the card, and never a bare
# pid, which a recycled pid would turn into a slug held forever.
#
# Exit codes: 0 ok, 1 no such card, 3 held, 4 no session process,
# 5 register unusable, 6 bad slug.
#
# Sourcing this file defines functions only. Executing it dispatches subcommands
# whose names and argument order match the functions one-for-one.
set -u

REGISTER_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$REGISTER_SELF_DIR/agent-team-register-lib.sh" ]; then
  # shellcheck source=hooks/agent-team-register-lib.sh
  . "$REGISTER_SELF_DIR/agent-team-register-lib.sh"
else
  printf 'register: agent-team-register-lib.sh is missing beside this script, so no claim can be resolved — the install is incomplete. Re-run: bash install.sh\n' >&2
  return 5 2>/dev/null || exit 5
fi

# Claim a change for this session. Behaviour, in order: validate the slug; resolve
# the session process; reap THIS card when its recorded process is dead or its
# content is empty or unparseable; if a card still exists, decide membership by
# decision 5 — a member is idempotent (exit 0), a non-member is refused (exit 3);
# otherwise create the card.
#
# A lost exclusive create is "held", full stop: no membership test is applied on
# that path — a claimant that started before the card existed is a loser, not a
# member.
#
# Membership ON THE CLAIM PATH is the recorded session ID (register_claim_member),
# not the recorded process. Decision 5's pid branch exists so that a subagent whose
# hook payload carries a different id can still resolve a claim its session made
# (register_mine, register_session_claims); applying it here would hand an existing
# claim to ANY process in the same tree, so twenty racing claimants would all be
# "members" and there would be twenty winners — no exclusion at all. The pid stays
# the liveness fact; the session id is the identity fact. Both real callers of
# `claim` — a fresh dispatch and a resumed session — carry the same session id,
# because a session keeps its id across a resume and gets a new process.
register_claim() { # $1 project-dir $2 slug $3 session-id
  register_valid_slug "$2" || {
    printf 'register: "%s" is not a legal change slug (lower-case letters, digits, dot, dash, underscore; no path separator, no "..")\n' \
      "$2" >&2
    return 6
  }
  local proj key card sp pid start json
  proj="$(register_project_root "$1")" || {
    printf 'register: %s is in no git repository, so no change can be claimed for it\n' "$1" >&2
    return 5
  }
  key="$(register_project_key "$proj")" || return 5
  card="$(register_root)/$key/$2.json"
  sp="$(register_session_process)" || {
    printf 'register: cannot resolve this session process, so a claim could never be released\n' >&2
    return 4
  }
  IFS=$'\t' read -r pid start <<< "$sp"
  register_ensure_dir "$(dirname "$card")" || return 5
  if [ -e "$card" ] && ! register_card_live "$card"; then
    rm -f "$card"
  fi
  if [ -e "$card" ]; then
    if register_claim_member "$card" "$3"; then
      printf '%s\n' "$card"
      return 0
    fi
    cat "$card"
    return 3
  fi
  json="$(register_new_card_json "$proj" "$key" "$2" "$3" "$pid" "$start")" || return 5
  if ( set -o noclobber; printf '%s\n' "$json" > "$card" ) 2>/dev/null; then
    printf '%s\n' "$card"
    return 0
  fi
  if [ -e "$card" ]; then
    cat "$card"
    return 3
  fi
  printf 'register: cannot create the timecard %s. Repair: mkdir -p %s\n' \
    "$card" "$(dirname "$card")" >&2
  return 5
}

# Is an existing card this claimant's own? Identity on the claim path is the
# session id alone; see the reasoning above register_claim.
register_claim_member() { # $1 card $2 session-id
  register_card_json_ok "$1" || return 1
  local csess
  csess="$(jq -r '.session // empty' "$1" 2>/dev/null)"
  [ -n "$csess" ] && [ "$csess" = "$2" ]
}

# Ordering is claim first, tree second, ready third (decision 4): a card only
# reaches `ready` once its workspace exists.
register_ready() { # $1 project-dir $2 slug
  local card
  card="$(register_resolve_card "$1" "$2")" || return $?
  register_write_merged "$card" '.state = "ready" | .heartbeat = $hb' \
    --argjson hb "$(date +%s)"
}

# The card's JSON when a LIVE claim exists; nothing and exit 1 otherwise, so a
# dead card never speaks for a holder.
register_holder() { # $1 project-dir $2 slug
  local card
  card="$(register_resolve_card "$1" "$2")" || return $?
  register_card_live "$card" || return 1
  cat "$card"
}

# Does this change belong to the caller? Prints which membership branch matched.
register_mine() { # $1 project-dir $2 slug $3 session-id
  local card sp pid start
  card="$(register_resolve_card "$1" "$2")" || return $?
  sp="$(register_session_process)" || return 4
  IFS=$'\t' read -r pid start <<< "$sp"
  register_card_member "$card" "$pid" "$start" "$3"
}

# One line per live card in this project that this session is a member of:
# `<slug><tab><worktree><tab><state>`. This is the candidate set a guard resolves
# an agent's workspace from — the register is the authority, and a dispatch
# declaration is only a selector among these.
register_session_claims() { # $1 project-dir $2 session-id
  local proj key dir card sp pid start slug
  proj="$(register_project_root "$1")" || return 5
  key="$(register_project_key "$proj")" || return 5
  dir="$(register_root)/$key"
  [ -d "$dir" ] || return 0
  sp="$(register_session_process)" || return 4
  IFS=$'\t' read -r pid start <<< "$sp"
  for card in "$dir"/*.json; do
    [ -e "$card" ] || continue
    register_card_live "$card" || continue
    register_card_member "$card" "$pid" "$start" "$2" >/dev/null || continue
    slug="$(basename "$card" .json)"
    printf '%s\t%s\t%s\n' "$slug" \
      "$(jq -r '.worktree // empty' "$card")" "$(jq -r '.state // empty' "$card")"
  done
}

# Deletes the card only when it is this session's or its process is dead; exit 3
# without deleting otherwise, so one session can never release another's claim.
register_release() { # $1 project-dir $2 slug [session-id]
  local card sp pid start sess
  card="$(register_resolve_card "$1" "$2")" || return $?
  sp="$(register_session_process)" || return 4
  IFS=$'\t' read -r pid start <<< "$sp"
  sess="${3:-$(jq -r '.session // empty' "$card" 2>/dev/null)}"
  if register_card_member "$card" "$pid" "$start" "$sess" >/dev/null \
    || ! register_card_live "$card"; then
    rm -f "$card"
    return 0
  fi
  printf 'register: %s is held by session %s, so this process may not release it\n' \
    "$2" "$(jq -r '.session // "unknown"' "$card")" >&2
  return 3
}

# The writer slot carries its OWN liveness — a heartbeat and a TTL — because a
# builder subagent that dies mid-task does not kill the session process the card
# records, so pid liveness alone could never free the slot. Granted when the slot
# is empty, when it is already this slot's, when the holder's heartbeat is older
# than writer_ttl_seconds, or when the card's session process is dead. A TTL
# displacement is a fail-open, recorded as one by the caller.
register_writer_acquire() { # $1 project-dir $2 slug $3 slot
  local card cur hb now ttl age
  card="$(register_resolve_card "$1" "$2")" || return $?
  cur="$(jq -r '.writer.slot // empty' "$card" 2>/dev/null)"
  hb="$(jq -r '.writer.heartbeat // empty' "$card" 2>/dev/null)"
  now="$(date +%s)"
  ttl="$(register_config_int writer_ttl_seconds 900)"
  case "$hb" in
    '' | *[!0-9]*) age=$((ttl + 1)) ;;
    *) age=$((now - hb)) ;;
  esac
  if [ -n "$cur" ] && [ "$cur" != "$3" ] && [ "$age" -le "$ttl" ] \
    && register_card_live "$card"; then
    printf 'register: the writer slot for %s is held by %s (%ss old, TTL %ss)\n' \
      "$2" "$cur" "$age" "$ttl" >&2
    return 3
  fi
  register_write_merged "$card" \
    '.writer = {slot:$slot, session:.session, heartbeat:$hb} | .heartbeat = $hb' \
    --arg slot "$3" --argjson hb "$now"
}

register_writer_release() { # $1 project-dir $2 slug
  local card
  card="$(register_resolve_card "$1" "$2")" || return $?
  register_write_merged "$card" '.writer = null'
}

# Refreshes the card's heartbeat, and the writer entry's too when a slot is given
# and it is the slot recorded.
register_heartbeat() { # $1 project-dir $2 slug [slot]
  local card
  card="$(register_resolve_card "$1" "$2")" || return $?
  register_write_merged "$card" \
    '.heartbeat = $hb
     | if $slot != "" and (.writer|type) == "object" and .writer.slot == $slot
       then .writer.heartbeat = $hb else . end' \
    --arg slot "${3:-}" --argjson hb "$(date +%s)"
}

# Reconciliation is a reap, never a deadlock: a card goes when it is unreadable or
# when its recorded process is gone. A card whose process is LIVE is never removed,
# whatever its age.
register_reap() { # $1 project-dir
  local proj key dir card slug
  proj="$(register_project_root "$1")" || return 5
  key="$(register_project_key "$proj")" || return 5
  dir="$(register_root)/$key"
  [ -d "$dir" ] || return 0
  for card in "$dir"/*.json; do
    [ -e "$card" ] || continue
    slug="$(basename "$card" .json)"
    if ! register_card_json_ok "$card"; then
      rm -f "$card"
      printf 'reaped %s unreadable-timecard\n' "$slug"
      continue
    fi
    if ! register_card_live "$card"; then
      rm -f "$card"
      printf 'reaped %s dead-session-process\n' "$slug"
    fi
  done
}

register_main() {
  local cmd="${1:-}"
  [ "$#" -gt 0 ] && shift
  case "$cmd" in
    claim) register_claim "$@" ;;
    ready) register_ready "$@" ;;
    holder) register_holder "$@" ;;
    mine) register_mine "$@" ;;
    release) register_release "$@" ;;
    reap) register_reap "$@" ;;
    writer-acquire) register_writer_acquire "$@" ;;
    writer-release) register_writer_release "$@" ;;
    heartbeat) register_heartbeat "$@" ;;
    session-claims) register_session_claims "$@" ;;
    card-path) register_card_path "$@" ;;
    worktree-path) register_worktree_path "$@" ;;
    *)
      printf 'register: unknown subcommand "%s". Known: claim ready holder mine release reap writer-acquire writer-release heartbeat session-claims card-path worktree-path\n' \
        "$cmd" >&2
      return 2
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  register_main "$@"
fi
