#!/usr/bin/env bash
# tools/worktree-hygiene.sh <repo> [--register] — read-only worktree hygiene report.
#
# Lists every registered worktree with evidence (branch, merged-into-main,
# tree-clean, last-commit age) and counts removal candidates: merged AND
# clean AND not the current worktree. Never deletes or mutates anything —
# a candidate is evidence for a human decision, not permission to act.
#
# `--register` adds the operator view of the work register: one line per timecard
# in this project — the change slug, the session holding it, whether that
# session's process is still alive, the claim's state, its writer slot and how
# old that slot's evidence is, when the claim was opened, and a `stale` marker
# past claim_stale_warn_seconds — followed by one line per registered worktree
# under `.claude/worktrees/` that no timecard covers, marked `unclaimed` with the
# exact command that removes it. Without the flag the report is byte-identical to
# what it was before the flag existed. With it, the tool is still read-only: it
# reads timecards, it never claims, releases, reaps or rewrites one, and a dead
# claim is reported as reapable rather than reaped.
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
REGISTER_SH="$SELF_DIR/../hooks/agent-team-register.sh"
REGISTER_LIB="$SELF_DIR/../hooks/agent-team-register-lib.sh"

REPO=""
SHOW_REGISTER=0
for arg in "$@"; do
  case "$arg" in
    --register) SHOW_REGISTER=1 ;;
    -*)
      echo "worktree-hygiene: unknown option $arg" >&2
      exit 0
      ;;
    *) [ -z "$REPO" ] && REPO="$arg" ;;
  esac
done
if [ -z "$REPO" ]; then
  echo "usage: worktree-hygiene.sh <repo> [--register]" >&2
  exit 0
fi

git -C "$REPO" rev-parse --show-toplevel >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "worktree-hygiene: $REPO is not a Git repository" >&2
  exit 0
fi

CURRENT="$(cd "$REPO" && pwd -P)"

BASE=""
for candidate in main master; do
  if git -C "$REPO" show-ref --verify --quiet "refs/heads/$candidate"; then
    BASE="$candidate"
    break
  fi
done
if [ -z "$BASE" ]; then
  BASE="$(git -C "$REPO" symbolic-ref --short -q HEAD || echo HEAD)"
fi

echo "worktree-hygiene: base=$BASE"

CANDIDATES=0
TOTAL=0

git -C "$REPO" worktree list --porcelain | {
  path=""
  branch=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch "*) branch="${line#branch refs/heads/}" ;;
      "detached") branch="(detached)" ;;
      "")
        if [ -n "$path" ]; then
          TOTAL=$((TOTAL + 1))
          resolved="$(cd "$path" 2>/dev/null && pwd -P)"

          clean="no"
          if [ -n "$resolved" ] && [ -z "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
            clean="yes"
          fi

          merged="no"
          if [ -n "$branch" ] && [ "$branch" != "(detached)" ] && [ "$branch" != "$BASE" ]; then
            if git -C "$REPO" merge-base --is-ancestor "$branch" "$BASE" 2>/dev/null; then
              merged="yes"
            fi
          fi

          age="unknown"
          last_commit_epoch="$(git -C "$path" log -1 --format=%ct 2>/dev/null)"
          if [ -n "$last_commit_epoch" ]; then
            now_epoch="$(date +%s)"
            age_days=$(( (now_epoch - last_commit_epoch) / 86400 ))
            age="${age_days}d"
          fi

          is_current="no"
          [ -n "$resolved" ] && [ "$resolved" = "$CURRENT" ] && is_current="yes"

          if [ "$merged" = "yes" ] && [ "$clean" = "yes" ] && [ "$is_current" = "no" ]; then
            printf '%s\tbranch=%s\tmerged=%s\tclean=%s\tage=%s\tcandidate\tremove: git worktree remove %s\n' \
              "$path" "${branch:-none}" "$merged" "$clean" "$age" "$path"
            CANDIDATES=$((CANDIDATES + 1))
          elif [ "$is_current" = "yes" ]; then
            printf '%s\tbranch=%s\tmerged=%s\tclean=%s\tage=%s\tkeep: current worktree\n' \
              "$path" "${branch:-none}" "$merged" "$clean" "$age"
          elif [ "$merged" = "no" ]; then
            printf '%s\tbranch=%s\tmerged=%s\tclean=%s\tage=%s\tkeep: unique commits\n' \
              "$path" "${branch:-none}" "$merged" "$clean" "$age"
          else
            printf '%s\tbranch=%s\tmerged=%s\tclean=%s\tage=%s\tkeep: dirty tree\n' \
              "$path" "${branch:-none}" "$merged" "$clean" "$age"
          fi
        fi
        path=""
        branch=""
        ;;
    esac
  done
  echo "$CANDIDATES removal candidate(s) of $TOTAL registered worktree(s)"
}

[ "$SHOW_REGISTER" -eq 1 ] || exit 0

# --- the operator view of the work register ---------------------------------
# Sourcing the register's library gives the derived names, the liveness test and
# the configured thresholds, so nothing here re-derives the project key or
# second-guesses what "live" means. The library defines functions only.
if [ ! -r "$REGISTER_LIB" ]; then
  echo "worktree-hygiene: the work register library is not readable at $REGISTER_LIB, so no claim can be listed"
  exit 0
fi
# shellcheck source=/dev/null
. "$REGISTER_LIB"

PROJ="$(register_project_root "$REPO")" || PROJ=""
if [ -z "$PROJ" ]; then
  echo "worktree-hygiene: $REPO resolves to no project root, so no claim can be listed"
  exit 0
fi
REG_KEY="$(register_project_key "$PROJ")" || REG_KEY=""
REG_DIR="$(register_root)/$REG_KEY"
NOW="$(date +%s)"
STALE_AFTER="$(register_config_int claim_stale_warn_seconds 86400)"
REAP_CMD="bash $REGISTER_SH reap $PROJ"

echo "worktree-hygiene: register=$REG_DIR stale_after=${STALE_AFTER}s"

# An ISO-8601 UTC stamp as epoch seconds: BSD date first, then GNU; empty when
# neither can parse it, and the caller then reports the age as unknown.
iso_epoch() { # $1 stamp
  local v
  v="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null)" \
    || v="$(date -u -d "$1" +%s 2>/dev/null)" || v=""
  printf '%s' "$v"
}

CLAIMS=0
CLAIMED=""                       # "|path|path|" — every tree a timecard covers
if [ -d "$REG_DIR" ]; then
  for card in "$REG_DIR"/*.json; do
    [ -f "$card" ] || continue
    slug="$(basename "$card" .json)"
    CLAIMS=$((CLAIMS + 1))
    if ! register_card_json_ok "$card"; then
      printf 'claim\t%s\tunreadable-timecard\treapable: %s\n' "$slug" "$REAP_CMD"
      continue
    fi
    # Every field carries a non-empty default on purpose: tab is IFS whitespace,
    # so an empty field would collapse and shift every field after it.
    IFS="$(printf '\t')" read -r sess pid start state wt slot slot_hb opened <<EOF
$(jq -r '[.session // "unknown", (.pid // "-" | tostring), .pid_start // "-",
          .state // "unknown", .worktree // "-",
          (if (.writer | type) == "object" then (.writer.slot // "?") else "none" end),
          (if (.writer | type) == "object" then (.writer.heartbeat // "-" | tostring) else "-" end),
          .opened // "-"] | @tsv' "$card")
EOF
    if register_alive "$pid" "$start"; then process="live"; else process="dead"; fi
    case "$slot_hb" in
      '' | *[!0-9]*) slot_age="-" ;;
      *) slot_age="$((NOW - slot_hb))s" ;;
    esac
    claim_epoch="$(iso_epoch "$opened")"
    case "$claim_epoch" in
      '' | *[!0-9]*) age="unknown"; stale="" ;;
      *)
        age="$((NOW - claim_epoch))s"
        if [ "$((NOW - claim_epoch))" -gt "$STALE_AFTER" ]; then
          stale="$(printf '\tstale')"
        else
          stale=""
        fi
        ;;
    esac
    [ "$process" = "dead" ] && stale="$stale$(printf '\treapable: %s' "$REAP_CMD")"
    printf 'claim\t%s\tsession=%s\tpid=%s\tprocess=%s\tstate=%s\twriter=%s\twriter_age=%s\topened=%s\tage=%s%s\n' \
      "$slug" "$sess" "$pid" "$process" "$state" "$slot" "$slot_age" \
      "$opened" "$age" "$stale"
    if [ "$wt" != "-" ]; then
      CLAIMED="$CLAIMED|$wt"
      resolved="$(cd "$wt" 2>/dev/null && pwd -P)"
      [ -n "$resolved" ] && CLAIMED="$CLAIMED|$resolved"
    fi
  done
fi
CLAIMED="$CLAIMED|"

UNCLAIMED=0
WT_PREFIX="$PROJ/.claude/worktrees/"
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in "worktree "*) path="${line#worktree }" ;; *) continue ;; esac
  case "$path" in "$WT_PREFIX"?*) ;; *) continue ;; esac
  covered=0
  case "$CLAIMED" in *"|$path|"*) covered=1 ;; esac
  resolved="$(cd "$path" 2>/dev/null && pwd -P)"
  if [ -n "$resolved" ]; then
    case "$CLAIMED" in *"|$resolved|"*) covered=1 ;; esac
  fi
  [ "$covered" -eq 1 ] && continue
  printf '%s\tunclaimed\tno timecard covers it\tremove: git worktree remove %s\n' \
    "$path" "$path"
  UNCLAIMED=$((UNCLAIMED + 1))
done <<EOF
$(git -C "$REPO" worktree list --porcelain 2>/dev/null)
EOF

printf '%s claim(s) in the register, %s unclaimed worktree(s) under %s\n' \
  "$CLAIMS" "$UNCLAIMED" "$WT_PREFIX"

exit 0
