#!/usr/bin/env bash
# tools/agent-team-scoreboard.sh — read-only aggregation over dispatch outcome
# records (docs/telemetry/*.jsonl). Evidence for a human recalibrating the
# orchestrator's routing table; no ranking, no side effects. Run from the repo:
#   bash tools/agent-team-scoreboard.sh [telemetry-dir]
# Spec: docs/superpowers/specs/2026-07-13-dispatch-telemetry-design.md §5.
set -u

ROOT="${1:-docs/telemetry}"
HERE="$(cd "$(dirname "$0")" && pwd)"
RATES="${AGENT_TEAM_RATES:-$HERE/../hooks/model-rates.json}"

header() { printf 'role  resolved_model  tier  n  first-try%%  pass%%  median$  drift\n'; }

if [ ! -d "$ROOT" ]; then
  header; echo "(no telemetry directory at $ROOT)"; exit 0
fi
if ! ls "$ROOT"/*.jsonl >/dev/null 2>&1; then
  header; echo "(no records under $ROOT)"; exit 0
fi
jq empty "$RATES" 2>/dev/null || { header; echo "(rates file $RATES missing or invalid — cannot quarantine unknown models)"; exit 0; }

# One jq pass over every line of every file. A line that is not a JSON object
# is skipped and counted, never an abort. Records whose resolved_model is
# null, "<synthetic>", or absent from the rates file are quarantined into the
# "unattributed" count — surfaced, never folded into a real model's row.
cat "$ROOT"/*.jsonl | jq -R -s -r --slurpfile rates "$RATES" '
  # two-decimal money string: 0.4 -> "0.40"
  def money2: (. * 100 | round) as $c
    | "\(($c / 100) | floor)." + (($c % 100) | tostring | if length < 2 then "0" + . else . end);
  def pct($num; $den): if $den == 0 then "—" else "\(($num / $den * 100) | round)%" end;
  def median: sort | length as $n
    | if $n == 0 then null
      elif ($n % 2) == 1 then .[(($n - 1) / 2)]
      else (.[($n / 2) - 1] + .[($n / 2)]) / 2 end;

  ($rates[0].models) as $M |
  (split("\n") | map(select(length > 0))) as $lines |
  ($lines | map((fromjson? // "__bad__") | if type == "object" then . else "__bad__" end)) as $parsed |
  ($parsed | map(select(. == "__bad__")) | length) as $malformed |
  ($parsed | map(select(. != "__bad__"))) as $recs |
  ($recs | map(select(.resolved_model as $rm |
      ($rm | type) != "string" or $rm == "<synthetic>"
      or (($M | has($rm)) | not)))) as $quarantined |
  ($recs - $quarantined) as $good |

  ( $good | group_by([.role, .resolved_model, .tier]) | map(
      map(select(.sequence == "first")) as $firsts |
      map(select(.verdict == "pass" or .verdict == "fail" or .verdict == "escalated")) as $judged |
      [ .[0].role, .[0].resolved_model, .[0].tier,
        (length | tostring),
        pct(($firsts | map(select(.verdict == "pass")) | length); ($firsts | length)),
        pct(($judged | map(select(.verdict == "pass")) | length); ($judged | length)),
        ((map(.cost_usd | select(type == "number")) | median) | if . == null then "—" else money2 end),
        (map(select(.model_drift == true)) | length | tostring)
      ] | join("\t")
    ) | .[] ),
  (if ($quarantined | length) > 0
   then "unattributed: \($quarantined | length) record(s) — resolved_model unset, synthetic, or not in the rates file"
   else empty end),
  (if $malformed > 0 then "skipped: \($malformed) malformed line(s)" else empty end),
  ( $good | map(select(.role == "builder" and (.framing // "n/a") != "n/a"))
    | group_by(.framing) | map("framing \(.[0].framing): \(length)") | .[] )
' | {
  # pretty columns without disturbing the footer lines
  header
  while IFS= read -r line; do
    case "$line" in
      unattributed:*|skipped:*|framing\ *:*) printf '%s\n' "$line" ;;
      *) printf '%s\n' "$line" | awk -F'\t' '{printf "%-10s %-18s %-9s %4s %10s %7s %8s %6s\n", $1,$2,$3,$4,$5,$6,$7,$8}' ;;
    esac
  done
}
exit 0
