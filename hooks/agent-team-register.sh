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
# The register is three files, split for the project's file-size discipline, and
# sourcing THIS one defines all of them: agent-team-register-lib.sh (derived names,
# liveness, membership, safe rewrites) and agent-team-register-writer.sh (the atomic
# take that every removal goes through, and the writer slot built on it).
#
# Sourcing this file defines functions only. Executing it dispatches subcommands
# whose names and argument order match the functions one-for-one.
set -u

REGISTER_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for register_sibling in agent-team-register-lib.sh agent-team-register-writer.sh; do
  if [ -r "$REGISTER_SELF_DIR/$register_sibling" ]; then
    # shellcheck source=/dev/null
    . "$REGISTER_SELF_DIR/$register_sibling"
  else
    printf 'register: %s is missing beside this script, so no claim can be resolved — the install is incomplete. Re-run: bash install.sh\n' \
      "$register_sibling" >&2
    return 5 2>/dev/null || exit 5
  fi
done
unset register_sibling

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
#
# An optional fourth argument names the worktree the human chose (2026-09-01). It is
# recorded on a NEW card only; an existing card already says where the change works, and
# the caller compares the two. Validation of the path — absolute, on disk, a worktree
# git lists for this project — is the workspace library's, not this file's.
register_claim() { # $1 project-dir $2 slug $3 session-id [$4 named-worktree]
  register_valid_slug "$2" || {
    printf 'register: "%s" is not a legal change slug (lower-case letters, digits, dot, dash, underscore; no path separator, no ".."; and because the ref name refs/heads/change/<slug> is derived from it, it may not end in a dot or in ".lock")\n' \
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
  # A dead card is TAKEN, never unlinked on a judgment: six claimants can all judge
  # one dead card dead in the same instant, and six unlinks would then land on
  # whichever fresh card was created first, leaving six winners. A lost take is not
  # an error — the path is re-read immediately below, which is where a card that
  # another claimant has already replaced is refused.
  if [ -e "$card" ]; then
    register_take_dead_card "$card" >/dev/null 2>&1 || :
  fi
  if [ -e "$card" ]; then
    if register_claim_member "$card" "$3"; then
      # Adoption RE-ANCHORS liveness (decision 5, recorded as a fail-open): a
      # resumed session keeps its id and gets a new process, so a card left naming
      # the pre-resume process reads dead the moment that process exits — after
      # which any reap frees a slug whose worktree this session is still writing in.
      register_write_merged "$card" '.pid = $pid | .pid_start = $start | .heartbeat = $hb' \
        --argjson pid "$pid" --arg start "$start" --argjson hb "$(date +%s)" \
        >/dev/null 2>&1
      printf '%s\n' "$card"
      return 0
    fi
    cat "$card"
    return 3
  fi
  json="$(register_new_card_json "$proj" "$key" "$2" "$3" "$pid" "$start" "${4:-}")" || return 5
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
  # An omitted session id is NO id, never the card's own: defaulting it to the
  # card's session would compare the card against itself, the session-id arm would
  # always match, and any process could delete any live claim. With no id given,
  # membership can only be established by the process arm.
  sess="${3:-}"
  if register_card_member "$card" "$pid" "$start" "$sess" >/dev/null \
    || ! register_card_live "$card"; then
    rm -f "$card"
    return 0
  fi
  printf 'register: %s is held by session %s, so this process may not release it\n' \
    "$2" "$(jq -r '.session // "unknown"' "$card")" >&2
  return 3
}

# Refreshes the card's heartbeat, and the writer entry's too when a slot is given
# and it is the slot recorded — in the slot file as well as in the card's mirror, so
# a refreshed slot never reads stale through either.
register_heartbeat() { # $1 project-dir $2 slug [slot]
  local card lock
  card="$(register_resolve_card "$1" "$2")" || return $?
  if [ -n "${3:-}" ]; then
    lock="$(register_writer_lock_path "$card")"
    if [ "$(jq -r '.slot // empty' "$lock" 2>/dev/null)" = "$3" ]; then
      register_write_merged "$lock" '.heartbeat = $hb' \
        --argjson hb "$(date +%s)" >/dev/null 2>&1
    fi
  fi
  register_write_merged "$card" \
    '.heartbeat = $hb
     | if $slot != "" and (.writer|type) == "object" and .writer.slot == $slot
       then .writer.heartbeat = $hb else . end' \
    --arg slot "${3:-}" --argjson hb "$(date +%s)"
}

# Reconciliation is a reap, never a deadlock: a card goes when it is unreadable or
# when its recorded process is gone. A card whose process is LIVE is never removed,
# whatever its age. The removal itself goes through register_take_dead_card, so a
# card that another process replaced between the judgment and the removal is left
# alone rather than destroyed. A reaped claim takes ITS OWN writer slot with it: the
# slot cannot outlive the claim it belonged to, but the slot file at that path may
# already belong to a FRESH claim on the same slug whose writer acquired it in the
# microseconds after the dead card was taken, so it is never unlinked by name. The
# session recorded in the dying card is read before the card goes, and the slot file
# is taken only when it records that same session AND the same `opened` stamp — the
# card's per-incarnation field. The session id alone is not enough: a resumed session
# keeps its id, so between this reap taking the dead card and unlinking its slot, that
# same session can have claimed the slug afresh and its writer can have taken the slot
# — and a take authorised by session id alone would then strip a LIVE writer's
# exclusion, after which a second writer is granted a slot nobody released. An
# unreadable card names neither field, so its slot is left to a TTL displacement rather
# than guessed at. Crash debris is swept last.
register_reap() { # $1 project-dir
  local proj key dir card slug reason sess opened
  proj="$(register_project_root "$1")" || return 5
  key="$(register_project_key "$proj")" || return 5
  dir="$(register_root)/$key"
  [ -d "$dir" ] || return 0
  for card in "$dir"/*.json; do
    [ -e "$card" ] || continue
    slug="$(basename "$card" .json)"
    if register_card_json_ok "$card"; then
      register_card_live "$card" && continue
      reason=dead-session-process
    else
      reason=unreadable-timecard
    fi
    sess="$(jq -r '.session // empty' "$card" 2>/dev/null)"
    opened="$(jq -r '.opened // empty' "$card" 2>/dev/null)"
    register_take_dead_card "$card" || continue
    register_writer_take_matching "$(register_writer_lock_path "$card")" \
      session "$sess" opened "$opened" || :
    printf 'reaped %s %s\n' "$slug" "$reason"
  done
  register_sweep_debris "$dir"
  register_sweep_debris "$dir/writers"
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
