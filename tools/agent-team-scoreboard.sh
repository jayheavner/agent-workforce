#!/usr/bin/env bash
# tools/agent-team-scoreboard.sh — read-only aggregation over machine telemetry
# records written by the closeout Stop hook via hooks/cost_report.py
# --telemetry-dir into the workforce-owned telemetry dir (never the client
# repo). One row per (role, model) with dispatch count and total cost in USD,
# sorted by cost descending. Evidence for a human recalibrating the roster's
# model pins; no side effects.
#   bash tools/agent-team-scoreboard.sh [telemetry-dir]
set -u

DEFAULT_ROOT="${AGENT_TEAM_TELEMETRY_DIR:-$HOME/.claude/logs/agent-team-telemetry}"
ROOT="${1:-$DEFAULT_ROOT}"

header() { printf '%-14s %-32s %10s %12s\n' role model dispatches cost_usd; }

if [ ! -d "$ROOT" ]; then
  header; echo "(no telemetry directory at $ROOT)"; exit 0
fi
if ! ls "$ROOT"/*.jsonl >/dev/null 2>&1; then
  header; echo "(no records under $ROOT)"; exit 0
fi

# One jq pass over every line of every file. A line that is not a JSON object is
# skipped and counted, never an abort. A dispatch that ran more than one model
# appears once, under the composite key "model1+model2" (resolved_models joined
# with "+") — its cost is counted once, never split or double-counted. Records
# whose role is "unknown" (the cost file could not attribute the dispatch) are
# summed into the "unattributed" bucket row, never folded into a real role's row.
cat "$ROOT"/*.jsonl | jq -R -s -r '
  def fmtrow: [.role, .model, (.n | tostring), (.cost | tostring)] | join("\t");

  (split("\n") | map(select(length > 0))) as $lines |
  ($lines | map((fromjson? // "__bad__") | if type == "object" then . else "__bad__" end)) as $parsed |
  ($parsed | map(select(. == "__bad__")) | length) as $malformed |
  ($parsed | map(select(. != "__bad__"))) as $recs |
  ($recs | map(select((.role // "unknown") == "unknown"))) as $unattr |
  ($recs | map(select((.role // "unknown") != "unknown"))) as $good |

  ( $good
    | group_by([.role, ((.resolved_models // []) | join("+"))])
    | map({role: .[0].role,
           model: (((.[0].resolved_models // []) | join("+")) | if . == "" then "(none)" else . end),
           n: length,
           cost: ((map(.cost_usd | select(type == "number")) | add) // 0)})
    | sort_by(-.cost)
    | .[] | fmtrow ),
  (if ($unattr | length) > 0
   then {role: "unattributed", model: "—", n: ($unattr | length),
         cost: ((($unattr | map(.cost_usd | select(type == "number"))) | add) // 0)} | fmtrow
   else empty end),
  (if $malformed > 0 then "skipped: \($malformed) malformed line(s)" else empty end),
  ( $good | map(select(.role == "builder" and (.framing // "n/a") != "n/a"))
    | group_by(.framing) | map("framing \(.[0].framing): \(length)") | .[] )
' | {
  # pretty columns without disturbing the footer line
  header
  while IFS= read -r line; do
    case "$line" in
      skipped:*) printf '%s\n' "$line" ;;
      *) printf '%s\n' "$line" | awk -F'\t' '{printf "%-14s %-32s %10s %12.4f\n", $1, $2, $3, $4}' ;;
    esac
  done
}
exit 0
