#!/usr/bin/env bash
# hooks/delivery-drift.sh — SessionStart hook. Reports when the local `main`
# ref holds commits `origin/main` does not, and when a `snapshot-*`/`backup-*`
# remote ref carries work that is not reachable from `origin/main` either.
#
# INFORMATIONAL ONLY. This never blocks or fails a session — it only prints a
# notice to stdout, or nothing at all. A delivery lag must not brick a turn.
#
# It is the inverse of hooks/landing-claim-verifier.sh: that hook fires when an
# agent CLAIMS delivery that did not happen; this one fires when delivery
# genuinely HAS NOT happened. The audit regime that verifier belongs to checks
# false claims of shipped work and checks nothing about work that never ships
# at all — that asymmetry is what let ~78 commits of finished, tested work sit
# undelivered on a project for two days while nine remote snapshot branches
# piled up as a holding pattern, unnoticed by anything until a human asked.
#
# MUST NEVER FETCH. Every check here reads local refs only — origin/main and
# origin/snapshot-*/backup-* as they already exist in this clone. A hook must
# not touch the network on every session start; the word "fetch" appears in
# this file only in comments saying so.
#
# Fail-open everywhere: `set -u` but never `set -e`; every git call is guarded
# and its status checked; git's own stderr is suppressed so a noisy failure
# never leaks into a session banner; the last line is an unconditional exit 0
# so nothing above it can propagate a non-zero status.
set -u

# Not a git work tree at all -> nothing to report, silently.
IN_TREE="$(git rev-parse --is-inside-work-tree 2>/dev/null)" || exit 0
[ "$IN_TREE" = "true" ] || exit 0

# No local main, or no origin/main to compare it against -> nothing to report.
git show-ref --verify --quiet refs/heads/main 2>/dev/null || exit 0
git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null || exit 0

# How far local main has run ahead of what was actually pushed. A failed or
# non-numeric read (should not happen once both refs above exist) falls open
# to 0 rather than ever surfacing a git error to the session.
N="$(git rev-list --count origin/main..main 2>/dev/null)"
case "$N" in
  '' | *[!0-9]*) N=0 ;;
esac

# Snapshot/backup remote refs that hold work unreachable from origin/main —
# exactly the holding-pattern shape this hook exists to catch. Each ancestry
# check is guarded on its own; a merge-base failure (e.g. a ref that vanished
# between the listing and the check) is treated as "not delivered" rather than
# aborting the scan.
UNDELIVERED=""
REFS="$(git for-each-ref --format='%(refname:short)' \
  'refs/remotes/origin/snapshot-*' 'refs/remotes/origin/backup-*' 2>/dev/null)"
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  if git merge-base --is-ancestor "$ref" origin/main 2>/dev/null; then
    continue
  fi
  UNDELIVERED="${UNDELIVERED:+$UNDELIVERED, }$ref"
done <<EOF
$REFS
EOF

if [ "$N" -gt 0 ] || [ -n "$UNDELIVERED" ]; then
  printf 'DELIVERY DRIFT: local main is %s commit(s) ahead of origin/main; this project delivers by pushing main (CI deploys on push). Undelivered refs: %s. Undelivered finished work is open work — integrate and push, or state the specific human decision that holds it.\n' \
    "$N" "${UNDELIVERED:-none}"
fi

exit 0
