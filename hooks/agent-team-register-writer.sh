#!/usr/bin/env bash
# hooks/agent-team-register-writer.sh — exclusion by the filesystem: the exclusive
# take that every removal in the register goes through, and the writer slot that
# rests on it.
#
# Why this is its own file. The register's other two halves decide things by reading
# state (whose claim is this, is that process alive). Everything here decides a fact two
# processes actively contend for — may I remove this timecard, may I write in this
# change — which a read followed by a write can never settle. So every decision here is
# one indivisible operation: an exclusive create (`>` under `noclobber`, which Bash opens
# with O_CREAT|O_EXCL) or a hard link pinning bytes so they cannot change under a
# judgment. Sourcing defines functions only — no side effects, no CLI; the register sources
# it beside agent-team-register-lib.sh and uses that library's liveness, rewrite and
# card-validity helpers. Exit codes are the register's: 1 no such card, 3 held, 5 unusable.

# The age reported for a slot with no usable heartbeat at all: older than any TTL a config
# could name, since a slot nobody refreshes is what a TTL is for. A constant, so no
# comparison special-cases an empty string.
REGISTER_AGE_INFINITE=2147483647

# Sixteen hex characters of a file's content SHA-256: the identity of the exact bytes a
# caller judged, so a removal is refused once those bytes have changed.
register_digest_file() { # $1 path
  local h=""
  if command -v shasum >/dev/null 2>&1; then
    h="$(shasum -a 256 < "$1" 2>/dev/null | awk '{print $1}')"
  elif command -v sha256sum >/dev/null 2>&1; then
    h="$(sha256sum < "$1" 2>/dev/null | awk '{print $1}')"
  fi
  [ -n "$h" ] || return 1
  printf '%s' "${h:0:16}"
}

# The right to remove a specific state of a specific path, won the same way a claim is won:
# an atomic exclusive create. The token names the taker's process, so an abandoned one is
# never mistaken for a holder.
register_take_token_claim() { # $1 token
  ( set -o noclobber
    printf '{"pid":%s,"pid_start":"%s"}\n' "$$" \
      "$(ps -p "$$" -o lstart= 2>/dev/null)" > "$1" ) 2>/dev/null
}

register_take_token_live() { # $1 token
  [ -s "$1" ] || return 1
  local pid start
  pid="$(jq -r '.pid // empty' "$1" 2>/dev/null)"
  start="$(jq -r '.pid_start // empty' "$1" 2>/dev/null)"
  register_alive "$pid" "$start"
}

# Remove a file EXACTLY ONCE, on behalf of a judgment the caller has already made about
# the bytes whose digest it passes. Concurrency is the whole point: N processes can all
# judge one dead timecard dead in the same instant, and if each then unlinks the path, the
# later unlinks land on the FRESH card the first one created and every one of them
# believes it won. So the right to remove THOSE BYTES is itself won by an exclusive create
# of a token named after them: exactly one process holds it, the losers refuse and re-read
# the path, and the holder re-checks the bytes before unlinking, so a path that changed
# hands meanwhile is never touched.
#
# A LOST create is a refusal, full stop, even when the token's taker is gone. The
# obvious-looking recovery — judge the taker dead, remove the token, create a fresh one —
# is the very check-then-act this function abolishes, and it hands one digest to two
# takers: both fail the create, both judge the taker dead, the first removes and
# re-creates, the second's removal takes the FIRST's fresh token and it re-creates in
# turn, so two processes hold "the" exclusive take and the later unlink lands on whatever
# the winner has put at the path. An abandoned token is therefore left to
# register_sweep_debris (in agent-team-register-lib.sh: a sweep is authorised by liveness,
# not by contention), which every reap runs last — the token goes as debris and the path
# is taken one cycle later.
register_take_file() { # $1 path $2 digest-of-the-judged-bytes
  local path="$1" want="${2:-}" token
  [ -n "$want" ] || return 1
  [ -f "$path" ] || return 1
  token="$(dirname "$path")/.take.$(basename "$path").$want"
  register_take_token_claim "$token" || return 1
  if [ "$(register_digest_file "$path" 2>/dev/null)" = "$want" ]; then
    rm -f "$path"
    rm -f "$token"
    return 0
  fi
  rm -f "$token"
  return 1
}

# Take a dead timecard away, and refuse to touch a live one. The card is first hard linked
# to a private name: every rewrite creates a NEW file and moves it over the card, so the
# linked bytes cannot change under us and the verdict, the digest and the removal describe
# one state of one card rather than three reads a racer can slip between.
register_take_dead_card() { # $1 card
  local card="$1" pin="$1.pin.$$" rc=1
  rm -f "$pin"
  ln "$card" "$pin" 2>/dev/null || return 1
  if register_card_json_ok "$pin" && register_card_live "$pin"; then
    rm -f "$pin"
    return 1
  fi
  register_take_file "$card" "$(register_digest_file "$pin" 2>/dev/null)" && rc=0
  rm -f "$pin"
  return "$rc"
}

# The writer slot's own file, in a SUBDIRECTORY of the project's register directory so no
# card glob can see it and no legal slug can collide with it: `writers/<slug>.json`.
register_writer_lock_path() { # $1 card
  printf '%s/writers/%s' "$(dirname "$1")" "$(basename "$1")"
}

# How old the evidence for a held slot is. The CARD's writer heartbeat is what a heartbeat
# call refreshes, so it is preferred whenever it names the same slot; the slot file's own
# heartbeat is the fallback, which is what makes a slot created milliseconds ago read as
# fresh before the card mirror has landed. No usable heartbeat reads as infinitely old.
register_writer_age() { # $1 card $2 slot-file $3 holder-slot $4 now
  local hb
  hb="$(jq -r --arg s "$3" '
    if (.writer | type) == "object" and .writer.slot == $s
    then (.writer.heartbeat // empty) else empty end' "$1" 2>/dev/null)"
  case "$hb" in '' | *[!0-9]*) hb="$(jq -r '.heartbeat // empty' "$2" 2>/dev/null)" ;; esac
  case "$hb" in '' | *[!0-9]*) printf '%s' "$REGISTER_AGE_INFINITE"; return 0 ;; esac
  printf '%s' "$(($4 - hb))"
}

# The card's mirror of the slot: what the operator view and the staleness heartbeat read.
# The slot file decides occupancy; this only records it.
register_writer_record() { # $1 card $2 slot $3 now
  register_write_merged "$1" \
    '.writer = {slot:$slot, session:.session, heartbeat:$hb} | .heartbeat = $hb' \
    --arg slot "$2" --argjson hb "$3"
}

# Displacing a stale slot is a removal, so it goes through the same take: pin the bytes,
# re-judge THOSE bytes, and only then take the path away. Never unlink on a judgment formed
# before a jq call another process could have written through.
register_writer_displace() { # $1 card $2 slot-file $3 ttl $4 now
  local pin="$2.stale.$$" cur age rc=1
  rm -f "$pin"
  ln "$2" "$pin" 2>/dev/null || return 1
  cur="$(jq -r '.slot // empty' "$pin" 2>/dev/null)"
  age="$(register_writer_age "$1" "$pin" "$cur" "$4")"
  if [ "$age" -gt "$3" ] || ! register_card_live "$1"; then
    register_take_file "$2" "$(register_digest_file "$pin" 2>/dev/null)" && rc=0
  fi
  rm -f "$pin"
  return "$rc"
}

# The writer slot is exclusive by the SAME primitive the claim is: an atomic exclusive
# create of a path. It cannot be a field inside the card guarded by a read — two guards
# firing from one dispatch message both read an empty slot, both merge their own name
# in, the second write wins, and both are told they may write. So the slot has its own
# file, `writers/<slug>.json`, created under noclobber and removed only by a
# digest-checked take the holding slot names itself in; the card keeps a mirror for the
# operator view and the staleness heartbeat.
#
# The slot also carries its own liveness — a heartbeat and a TTL — because a builder
# subagent that dies mid-task does not kill the session process the card records, so pid
# liveness alone could never free the slot. Granted when the slot file does not exist, when
# it is already this dispatch's, or when the holder has lapsed (heartbeat older than
# writer_ttl_seconds, or session process dead) AND no dispatch of this change is known to
# be in flight — the fifth argument, which is what keeps a timeout meant for a crashed
# writer off a live one. A displacement is a fail-open, recorded as one by the caller.
register_writer_acquire() { # $1 project-dir $2 slug $3 slot [$4 dispatch id] [$5 in flight]
  local card lock now ttl cur age json flight
  card="$(register_resolve_card "$1" "$2")" || return $?
  lock="$(register_writer_lock_path "$card")"
  register_ensure_dir "$(dirname "$lock")" || return 5
  now="$(date +%s)"
  ttl="$(register_config_int writer_ttl_seconds 900)"
  # A timeout displaces a writer NOBODY is behind. The caller may know that somebody is:
  # the dispatch guard counts the dispatches of this change its transcript still shows
  # unresolved, and passes that count here. Nothing refreshes a heartbeat during work, so a
  # lapsed heartbeat is NOT evidence of a dead writer — an honest build past the TTL reads
  # exactly like a crash, and the slot then guarded only the first quarter of an hour. An
  # absent or non-numeric count is 0: a caller holding no such evidence keeps the plain TTL
  # behaviour rather than a change nobody can recover.
  flight="${5:-0}"
  case "$flight" in '' | *[!0-9]*) flight=0 ;; esac
  # The slot records whose it is: the session, the card's `opened` stamp (the one field that
  # changes on every incarnation of the claim) and, from the optional fourth argument, an
  # identifier of the DISPATCH that took it — the only fact separating two dispatches of one
  # role in one session on one claim incarnation, as register_writer_slot_is_ours explains.
  json="$(jq -cn --arg slot "$3" --argjson hb "$now" --arg disp "${4:-}" \
    --arg sess "$(jq -r '.session // empty' "$card" 2>/dev/null)" \
    --arg opened "$(jq -r '.opened // empty' "$card" 2>/dev/null)" \
    '{slot:$slot,session:$sess,opened:$opened,dispatch:$disp,heartbeat:$hb}')" || return 5
  if register_writer_slot_create "$lock" "$json"; then
    register_writer_record "$card" "$3" "$now"
    return
  fi
  # A failed create is not evidence of a holder, exactly as on the claim path.
  [ -f "$lock" ] || {
    printf 'register: cannot create the writer slot file %s. Repair: mkdir -p %s\n' \
      "$lock" "$(dirname "$lock")" >&2
    return 5
  }
  cur="$(jq -r '.slot // empty' "$lock" 2>/dev/null)"
  if [ -n "$cur" ] && [ "$cur" = "$3" ] \
    && register_writer_slot_is_ours "$card" "$lock" "${4:-}"; then
    register_write_merged "$lock" '.heartbeat = $hb' --argjson hb "$now" >/dev/null 2>&1
    register_writer_record "$card" "$3" "$now"
    return
  fi
  age="$(register_writer_age "$card" "$lock" "$cur" "$now")"
  if [ "$age" -gt "$ttl" ] && [ "$flight" -gt 0 ] && register_card_live "$card"; then
    printf 'register: the writer slot for %s is held by %s, whose dispatch is still in flight (%ss since its last heartbeat, TTL %ss), so the timeout does not displace it\n' \
      "$2" "${cur:-an unnamed writer}" "$age" "$ttl" >&2
    return 3
  fi
  if [ "$age" -le "$ttl" ] && register_card_live "$card"; then
    printf 'register: the writer slot for %s is held by %s (%ss old, TTL %ss)\n' \
      "$2" "${cur:-an unnamed writer}" "$age" "$ttl" >&2
    return 3
  fi
  if register_writer_displace "$card" "$lock" "$ttl" "$now" \
    && register_writer_slot_create "$lock" "$json"; then
    register_writer_record "$card" "$3" "$now"
    return
  fi
  printf 'register: the writer slot for %s could not be displaced; %s holds it now\n' \
    "$2" "$(jq -r '.slot // "an unnamed writer"' "$lock" 2>/dev/null)" >&2
  return 3
}

# Does the slot file record THIS incarnation of the claim — the session and the card's
# current `opened` stamp — AND, when either side names one, this same dispatch? A matching
# slot NAME is not identity: the name is `<role>#<n>` counted from a transcript, so two
# dispatches whose transcript cannot be read both compute `builder#0`, and session plus
# `opened` do not separate them either, since two dispatches of one session against one
# claim incarnation share both. The dispatch identifier is the third fact and the only one
# that differs, so a slot recording one is never re-entered by a caller naming a different
# one or naming none: that is a sibling asking for a turn somebody else holds. Unreadable
# either side is a NO.
register_writer_slot_is_ours() { # $1 card $2 slot-file [$3 dispatch id]
  local want got disp
  want="$(jq -r '[(.session // ""), (.opened // "")] | @tsv' "$1" 2>/dev/null)"
  got="$(jq -r '[(.session // ""), (.opened // "")] | @tsv' "$2" 2>/dev/null)"
  [ -n "$want" ] && [ "$want" = "$got" ] || return 1
  disp="$(jq -r '.dispatch // ""' "$2" 2>/dev/null)"
  [ -z "$disp" ] || [ "$disp" = "${3:-}" ]
}

# The one operation that decides occupancy. The noclobber is set HERE, in this subshell,
# and the redirection is `>`, which Bash opens with O_CREAT|O_EXCL.
register_writer_slot_create() { # $1 slot-file $2 json
  ( set -o noclobber; printf '%s\n' "$2" > "$1" ) 2>/dev/null
}

# Take the slot file away only when the values it RECORDS are the ones the caller claims
# authority from: the holding slot's own name on the release path, the reaped card's
# session AND `opened` stamp on the reap path. The bytes are pinned first, the fields read
# from the pinned bytes, and the removal is the same digest-checked take as every other —
# so a slot file another process replaced between the read and the removal is left alone.
# A second field/value pair is optional and, when given, must ALSO match; an empty wanted
# value never matches, since `// empty` equates "field absent" with "caller named nothing".
# Exit 0 when the path was taken, 1 when it was not this caller's to take.
register_writer_take_matching() { # $1 slot-file $2 field $3 value [$4 field $5 value]
  local pin="$1.pin.$$" rc=1 matched=1
  [ -f "$1" ] || return 1
  [ -n "${3:-}" ] || return 1
  rm -f "$pin"
  ln "$1" "$pin" 2>/dev/null || return 1
  [ "$(jq -r --arg f "$2" '.[$f] // empty' "$pin" 2>/dev/null)" = "$3" ] || matched=0
  if [ -n "${4:-}" ]; then
    [ -n "${5:-}" ] \
      && [ "$(jq -r --arg f "$4" '.[$f] // empty' "$pin" 2>/dev/null)" = "$5" ] \
      || matched=0
  fi
  if [ "$matched" -eq 1 ]; then
    register_take_file "$1" "$(register_digest_file "$pin" 2>/dev/null)" && rc=0
  fi
  rm -f "$pin"
  return "$rc"
}

# Releasing the slot is a REMOVAL of the one file that decides occupancy, so it is
# authorised like every other removal: the caller names the slot it holds, and only that
# slot's own file may be taken. A release that took no slot name and unlinked the path
# unconditionally let ANY process — a foreign session, or another subagent of the same one
# — drop the holder's exclusion, after which a third acquirer was granted a slot two
# processes believed they held. The card's mirror is nulled only after a successful take,
# and only while it still names this slot.
# Exit 2 when no slot is named, 3 when the slot named is not the holder.
register_writer_release() { # $1 project-dir $2 slug $3 slot
  local card lock cur slot="${3:-}"
  [ -n "$slot" ] || {
    printf 'register: writer-release needs the slot that holds it, so a foreign process cannot drop the holder exclusion. Usage: writer-release <project-dir> <slug> <slot>\n' >&2
    return 2
  }
  card="$(register_resolve_card "$1" "$2")" || return $?
  lock="$(register_writer_lock_path "$card")"
  if [ -f "$lock" ] && ! register_writer_take_matching "$lock" slot "$slot"; then
    cur="$(jq -r '.slot // empty' "$lock" 2>/dev/null)"
    # The caller IS the holder, and what stopped the take is a stranded removal token
    # for the slot file's current bytes. Saying "held by <caller>, so <caller> may not
    # release it" named the caller as its own obstacle, which reads as a defect rather
    # than as the one-cycle wait it is.
    if [ -n "$cur" ] && [ "$cur" = "$slot" ]; then
      printf 'register: %s is still the writer of %s and the slot file is unchanged, but a stranded removal token for its current state stands beside it at %s, so the file cannot be taken away yet. Nothing is lost — every reap sweeps an abandoned token, after which this same release succeeds. Repair: bash %s/agent-team-register.sh reap %s, then writer-release %s %s %s\n' \
        "$slot" "$2" "$(dirname "$lock")" \
        "${REGISTER_SELF_DIR:-$(dirname "${BASH_SOURCE[0]}")}" "$1" "$1" "$2" "$slot" >&2
      return 3
    fi
    printf 'register: the writer slot for %s is held by %s, so %s may not release it\n' \
      "$2" "${cur:-an unnamed writer}" "$slot" >&2
    return 3
  fi
  register_writer_unrecord "$card" "$slot"
}

# The card's mirror stops naming a slot that no longer holds one. Conditional on the slot:
# the mirror is only ever this slot's to clear.
register_writer_unrecord() { # $1 card $2 slot
  register_write_merged "$1" \
    'if (.writer | type) == "object" and .writer.slot == $slot then .writer = null else . end' \
    --arg slot "$2" >/dev/null 2>&1
  return 0
}

# Tearing the whole change down, a different act from a slot holder stepping out of it:
# workspace_integrate has already established that the claim is the caller's own and is
# removing the claim itself, so the slot goes with it whoever holds it — there is no
# change left for a holder to write in. Unconditional BY DESIGN; the slot-scoped path is
# register_writer_release, which refuses a foreign slot.
register_writer_teardown() { # $1 project-dir $2 slug
  local card
  card="$(register_resolve_card "$1" "$2")" || return $?
  rm -f "$(register_writer_lock_path "$card")"
  register_write_merged "$card" '.writer = null' >/dev/null 2>&1
  return 0
}
