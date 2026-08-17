#!/usr/bin/env bash
# tests/lib/slow-claimant.sh — a real claimant that holds one interleaving open.
#
# Why this exists. The dangerous interleaving on the claim path is: two processes
# both judge the same card dead, and the second one's removal lands on the fresh
# card the first one created. In production that window is a few milliseconds wide,
# so racing plain claimants reproduces it roughly never — which is exactly how the
# defect survived a green test suite. This claimant sources the register and wraps
# `register_card_live` so that the verdict is computed first and the process then
# pauses before acting on it. Six of these started together therefore all hold a
# "this card is dead" verdict at the same instant, which is the interleaving in its
# worst form rather than a lucky one.
#
# Nothing here mocks the register: every decision is made by the real functions in
# hooks/agent-team-register.sh, in a real separate process, against a real card on
# disk. Only the timing is exaggerated.
#
# The pause is <stagger-seconds> multiplied by this racer's RACER_INDEX, so the
# racers act on their verdicts at DIFFERENT moments. A single shared pause would
# synchronise them so tightly that every removal lands before any creation — the
# benign ordering. Staggering is what puts a lagging removal after the winner's
# fresh card, which is the interleaving that destroys a live claim.
#
# Usage: slow-claimant.sh <stagger-seconds> <project-root> <slug> <session-id>
set -u

SLOW_LIB_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=hooks/agent-team-register.sh
. "$SLOW_LIB_DIR/../../hooks/agent-team-register.sh"

# Keep the real implementation under a second name, then wrap it.
eval "$(declare -f register_card_live | sed '1s/register_card_live/register_card_live_real/')"

SLOW_PAUSE="$(awk -v u="$1" -v i="${RACER_INDEX:-1}" 'BEGIN { printf "%.3f", u * i }')"
shift

register_card_live() {
  local rc=0
  register_card_live_real "$@" || rc=$?
  sleep "$SLOW_PAUSE"
  return "$rc"
}

register_claim "$@"
