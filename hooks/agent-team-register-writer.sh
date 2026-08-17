#!/usr/bin/env bash
# hooks/agent-team-register-writer.sh — exclusion by the filesystem: the exclusive
# take that every removal in the register goes through, and the writer slot that
# rests on it.
#
# Why this is its own file. The register's other two halves decide things by reading
# state (whose claim is this, is that process still alive). Everything here decides a
# fact that two processes are actively contending for — may I remove this timecard,
# may I write in this change — and a contended fact can never be settled by a read
# followed by a write. Every decision in this file is therefore made by an operation
# the operating system performs indivisibly: an exclusive create (`>` under
# `noclobber`, which Bash opens with O_CREAT|O_EXCL) or a hard link that pins bytes
# so they cannot change under a judgment.
#
# Sourcing defines functions only; this file has no side effects and no CLI. It is
# sourced by agent-team-register.sh alongside agent-team-register-lib.sh, and it uses
# that library's liveness, rewrite, and card-validity helpers.
#
# Exit codes shared with the register: 1 no such card, 3 held, 5 register unusable.

# The age reported for a slot with no usable heartbeat at all: older than any TTL a
# config could name, because a slot nobody is refreshing is exactly what a TTL is
# for. Kept as a constant so no comparison has to special-case an empty string.
REGISTER_AGE_INFINITE=2147483647

# Sixteen hex characters of a file's content SHA-256: the identity of the exact
# bytes a caller judged, so a removal can be refused when those bytes have changed.
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

# The right to remove a specific state of a specific path, won the same way a claim
# is won: an atomic exclusive create. The token names the taker's process so an
# abandoned one is never mistaken for a holder.
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

# Remove a file EXACTLY ONCE, on behalf of a judgment the caller has already made
# about the bytes whose digest it passes. Concurrency is the whole point: N
# processes can all judge one dead timecard dead in the same instant, and if each of
# them then unlinks the path, the later unlinks land on the FRESH card the first one
# created and every one of them believes it won. So the right to remove THOSE BYTES
# is itself won by an exclusive create of a token named after them: exactly one
# process can hold it, the losers refuse and re-read the path, and the holder
# re-checks the bytes before unlinking, so a path that changed hands meanwhile is
# never touched. A token whose creating process is gone is abandoned debris, not a
# holder — the same rule the register applies to timecards — so it is removed and
# the create retried once.
register_take_file() { # $1 path $2 digest-of-the-judged-bytes
  local path="$1" want="${2:-}" token
  [ -n "$want" ] || return 1
  [ -f "$path" ] || return 1
  token="$(dirname "$path")/.take.$(basename "$path").$want"
  if ! register_take_token_claim "$token"; then
    register_take_token_live "$token" && return 1
    rm -f "$token"
    register_take_token_claim "$token" || return 1
  fi
  if [ "$(register_digest_file "$path" 2>/dev/null)" = "$want" ]; then
    rm -f "$path"
    rm -f "$token"
    return 0
  fi
  rm -f "$token"
  return 1
}

# Take a dead timecard away, and refuse to touch a live one. The card is first hard
# linked to a private name: every rewrite creates a NEW file and moves it over the
# card, so the linked bytes can no longer change under us, and the verdict, the
# digest, and the removal therefore all describe one state of one card instead of
# three separate reads a racer can slip between.
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

# The writer slot's own file. It lives in a SUBDIRECTORY of the project's register
# directory so that no card glob can see it and no legal slug can ever collide with
# it: `writers/<slug>.json` beside `<slug>.json`.
register_writer_lock_path() { # $1 card
  printf '%s/writers/%s' "$(dirname "$1")" "$(basename "$1")"
}

# How old the evidence for a held slot is. The CARD's writer heartbeat is what a
# heartbeat call refreshes, so it is preferred whenever it names the same slot; the
# slot file's own heartbeat is the fallback, and it is what makes a slot created
# milliseconds ago read as fresh even before the card mirror has landed. No usable
# heartbeat at all reads as infinitely old.
register_writer_age() { # $1 card $2 slot-file $3 holder-slot $4 now
  local hb
  hb="$(jq -r --arg s "$3" '
    if (.writer | type) == "object" and .writer.slot == $s
    then (.writer.heartbeat // empty) else empty end' "$1" 2>/dev/null)"
  case "$hb" in '' | *[!0-9]*) hb="$(jq -r '.heartbeat // empty' "$2" 2>/dev/null)" ;; esac
  case "$hb" in '' | *[!0-9]*) printf '%s' "$REGISTER_AGE_INFINITE"; return 0 ;; esac
  printf '%s' "$(($4 - hb))"
}

# The card's mirror of the slot: what the operator view and the staleness heartbeat
# read. The slot file decides occupancy; this only records it.
register_writer_record() { # $1 card $2 slot $3 now
  register_write_merged "$1" \
    '.writer = {slot:$slot, session:.session, heartbeat:$hb} | .heartbeat = $hb' \
    --arg slot "$2" --argjson hb "$3"
}

# Displacing a stale slot is a removal, so it goes through the same take: pin the
# bytes, re-judge THOSE bytes, and only then take the path away. Never unlink on a
# judgment formed before a jq call that another process could have written through.
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

# Crash debris: a merged rewrite's temp file (`<card>.rewrite.<pid>`), a take's pin
# (`<card>.pin.<pid>`), a displacer's pin (`<slot-file>.stale.<pid>`), and an
# abandoned take token. None of them can ever be read as a timecard — no card glob
# matches them — but nothing swept them either, so a crash between the jq and the mv
# of a rewrite left one behind forever. A file whose trailing pid is gone, and a
# token whose taker is gone, have no owner that could still be writing them.
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

# The writer slot is exclusive by the SAME primitive the claim is: an atomic
# exclusive create of a path. It cannot be a field inside the card guarded by a read
# — two guards firing from one dispatch message both read an empty slot, both merge
# their own name into the card, the second write wins, and both are told they may
# write. So the slot has its own file, `writers/<slug>.json`, created under
# noclobber and released by unlink; the card keeps a mirror of it for the operator
# view and for the heartbeat that decides staleness.
#
# The slot also carries its own liveness — a heartbeat and a TTL — because a builder
# subagent that dies mid-task does not kill the session process the card records, so
# pid liveness alone could never free the slot. Granted when the slot file does not
# exist, when it is already this slot's, when the holder's heartbeat is older than
# writer_ttl_seconds, or when the card's session process is dead. A TTL displacement
# is a fail-open, recorded as one by the caller.
register_writer_acquire() { # $1 project-dir $2 slug $3 slot
  local card lock now ttl cur age json
  card="$(register_resolve_card "$1" "$2")" || return $?
  lock="$(register_writer_lock_path "$card")"
  register_ensure_dir "$(dirname "$lock")" || return 5
  now="$(date +%s)"
  ttl="$(register_config_int writer_ttl_seconds 900)"
  json="$(jq -cn --arg slot "$3" --argjson hb "$now" \
    --arg sess "$(jq -r '.session // empty' "$card" 2>/dev/null)" \
    '{slot:$slot,session:$sess,heartbeat:$hb}')" || return 5
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
  if [ -n "$cur" ] && [ "$cur" = "$3" ]; then
    register_write_merged "$lock" '.heartbeat = $hb' --argjson hb "$now" >/dev/null 2>&1
    register_writer_record "$card" "$3" "$now"
    return
  fi
  age="$(register_writer_age "$card" "$lock" "$cur" "$now")"
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

# The one operation that decides occupancy. The noclobber is set HERE, in this
# subshell, and the redirection is `>`, which Bash opens with O_CREAT|O_EXCL.
register_writer_slot_create() { # $1 slot-file $2 json
  ( set -o noclobber; printf '%s\n' "$2" > "$1" ) 2>/dev/null
}

register_writer_release() { # $1 project-dir $2 slug
  local card
  card="$(register_resolve_card "$1" "$2")" || return $?
  rm -f "$(register_writer_lock_path "$card")"
  register_write_merged "$card" '.writer = null'
}
