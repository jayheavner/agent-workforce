#!/usr/bin/env bash
# agent-team-cost.sh — PostToolUse(Agent) hook: sums exact per-request token
# usage from this session's per-dispatch subagent transcripts into a per-session
# cost file, priced from model-rates.json. Never blocks, never emits a wrong
# number: on any unrecognized input it writes a sticky "unavailable" marker and
# exits 0. See docs/superpowers/specs/2026-07-08-exact-closeout-cost-accounting-design.md.
set -u

INPUT="$(cat)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty')"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty')"
AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.tool_response.agentId // empty')"
AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.tool_response.agentType // "unknown"')"

# Cannot even locate a cost file safely -> write nothing, exit 0.
[ -n "$SESSION_ID" ] || exit 0
[ -n "$TRANSCRIPT" ] || exit 0

HERE="$(cd "$(dirname "$0")" && pwd)"
RATES="${AGENT_TEAM_RATES:-$HERE/model-rates.json}"
COST_DIR="${AGENT_TEAM_COST_DIR:-$HOME/.claude/logs/agent-team-cost}"
SUBAGENTS_DIR="${TRANSCRIPT%.jsonl}/subagents"
SLUG="$(printf '%s' "$CWD" | tr '/' '-')"
COST_FILE="$COST_DIR/$SLUG--$SESSION_ID.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$COST_DIR"

# write_unavailable REASON -> sticky marker, exit 0.
write_unavailable() {
  printf '%s' "$(jq -n --arg sid "$SESSION_ID" --arg cwd "$CWD" --arg now "$NOW" --arg r "$1" \
    '{version:1, session_id:$sid, cwd:$cwd, updated_at:$now, status:"unavailable", unavailable_reason:$r}')" \
    > "$COST_FILE"
  exit 0
}

# Load rates; unreadable/invalid rates -> unavailable.
jq empty "$RATES" 2>/dev/null || write_unavailable "rates file $RATES is missing or not JSON"

# parse_dispatch FILE AGENT_TYPE -> prints the per-dispatch JSON object on
# stdout on success, or a one-line reason on stderr and a non-zero exit on any
# recognition failure. One jq program per dispatch file: dedups by
# message.id, sums the five token classes per model, prices each logical
# request against the rates by its timestamp, and emits the per-dispatch
# object. See spec Component 1 step 5 for the recognition rules (a)-(e).
parse_dispatch() { # $1 file, $2 agent_type
  local file="$1" atype="$2" size
  size="$(wc -c < "$file" | tr -d ' ')"
  # (a) every line must be a JSON object.
  jq -e . "$file" >/dev/null 2>&1 || { echo "unparseable line in $(basename "$file")"; return 1; }
  jq -n \
    --slurpfile recs <(jq -s '.' "$file") \
    --slurpfile rates "$RATES" \
    --arg atype "$atype" --arg file "$file" --argjson size "$size" '
    # Suppress IEEE-754 binary-representation noise (e.g. 0.061+0.0555 prints
    # as 0.11649999999999999) without rounding to cents: costs at this scale
    # never carry more than ~10 significant decimal digits, so snapping to 10
    # decimal places removes only artifact noise, never real precision. The
    # spec'\''s "accumulate at full floating-point precision" rule concerns
    # cent-rounding for DISPLAY; this is binary-representation cleanup, applied
    # uniformly to every emitted cost_usd (per-request, per-model, grand total).
    def nofloat: (. * 10000000000 | round) / 10000000000;
    ($rates[0].models) as $M |
    ($recs[0]) as $R |
    # Assistant records that actually carry usage.
    [ $R[] | select(.type=="assistant" and (.message.usage != null)) ] as $U |
    # (b) shape recognition on each usage record.
    ( $U | map(
        (.message.id|type=="string") and
        (.message.model|type=="string" and (.|length>0)) and
        (.message.usage.input_tokens|type=="number") and
        (.message.usage.cache_creation_input_tokens|type=="number") and
        (.message.usage.cache_read_input_tokens|type=="number")
      ) | all ) as $shape_ok |
    if ($shape_ok|not) then {error:"malformed usage record shape"} else
    # Skip synthetic error model; strip trailing [1m].
    [ $U[] | .m = (.message.model | sub("\\[1m\\]$";"")) | select(.m != "<synthetic>") ] as $U2 |
    # (e) every model must be priceable.
    ( [ $U2[].m ] | unique ) as $models |
    if ([ $models[] | in($M) ] | all | not) then {error:"model not in rates config"} else
    # (c) within each message.id group, input & cache identical across snapshots.
    ( $U2 | group_by(.message.id) ) as $grp |
    ( $grp | map(
        (map(.message.usage.input_tokens)|unique|length==1) and
        (map(.message.usage.cache_creation_input_tokens)|unique|length==1) and
        (map(.message.usage.cache_read_input_tokens)|unique|length==1)
      ) | all ) as $dedup_ok |
    if ($dedup_ok|not) then {error:"snapshot input/cache mismatch within message id"} else
    # (d) when cache_creation present, 5m+1h == cache_creation_input_tokens.
    ( $U2 | map(select(.message.usage.cache_creation != null) |
        (.message.usage.cache_creation.ephemeral_5m_input_tokens + .message.usage.cache_creation.ephemeral_1h_input_tokens)
          == .message.usage.cache_creation_input_tokens
      ) | all ) as $split_ok |
    if ($split_ok|not) then {error:"cache_creation split does not sum to cache_creation_input_tokens"} else
    # One logical request per message.id: pick a representative (first) for
    # input/cache, take MAX output across the group.
    ( $grp | map({
        m: .[0].m,
        ts: .[0].timestamp,
        input:  .[0].message.usage.input_tokens,
        cread:  .[0].message.usage.cache_read_input_tokens,
        cw5m:   (if .[0].message.usage.cache_creation then .[0].message.usage.cache_creation.ephemeral_5m_input_tokens
                 else .[0].message.usage.cache_creation_input_tokens end),
        cw1h:   (if .[0].message.usage.cache_creation then .[0].message.usage.cache_creation.ephemeral_1h_input_tokens
                 else 0 end),
        output: (map(.message.usage.output_tokens // 0) | max)
      }) ) as $reqs |
    # Price each request by its date against std or intro rates.
    ( $reqs | map(
        ($M[.m]) as $mr |
        (if ($mr.intro != null) and (.ts[0:10] <= $mr.intro.ends) then $mr.intro else $mr end) as $r |
        . + { cost: ( (.input*$r.input + .output*$r.output + .cw5m*$r.cache_write_5m
                       + .cw1h*$r.cache_write_1h + .cread*$r.cache_read) / 1000000 ) }
      ) ) as $priced |
    # Aggregate per model.
    ( $priced | group_by(.m) | map({
        key: .[0].m,
        value: {
          input_tokens: (map(.input)|add),
          output_tokens: (map(.output)|add),
          cache_write_5m_tokens: (map(.cw5m)|add),
          cache_write_1h_tokens: (map(.cw1h)|add),
          cache_read_tokens: (map(.cread)|add),
          cost_usd: (map(.cost)|add|nofloat)
        }
      }) | from_entries ) as $bymodel |
    # server_tool_use tallies (billed per use, counted not priced).
    ( [ $U[] | .message.usage.server_tool_use.web_search_requests // 0 ] | add // 0 ) as $ws |
    ( [ $U[] | .message.usage.server_tool_use.web_fetch_requests // 0 ] | add // 0 ) as $wf |
    { agent_type: $atype, file: $file, file_size: $size,
      requests: ($reqs|length), models: $bymodel,
      web_search_requests: $ws, web_fetch_requests: $wf }
    end end end end
  '
}

# Scan the whole subagents dir every fire (D4: not just the just-fired
# dispatch) so an earlier dispatch's cost is never missing from the totals.
DISPATCHES='{}'
if [ -d "$SUBAGENTS_DIR" ]; then
  for f in "$SUBAGENTS_DIR"/agent-*.jsonl; do
    [ -e "$f" ] || continue
    aid="$(basename "$f")"; aid="${aid#agent-}"; aid="${aid%.jsonl}"
    atype="unknown"; [ "$aid" = "$AGENT_ID" ] && atype="$AGENT_TYPE"
    entry="$(parse_dispatch "$f" "$atype")" || write_unavailable "$(basename "$f"): $entry"
    if printf '%s' "$entry" | jq -e '.error' >/dev/null 2>&1; then
      write_unavailable "$(basename "$f"): $(printf '%s' "$entry" | jq -r .error)"
    fi
    DISPATCHES="$(jq -n --argjson d "$DISPATCHES" --arg k "$aid" --argjson v "$entry" '$d + {($k):$v}')"
  done
fi

# Roll up totals across all dispatch entries.
DOC="$(jq -n --arg sid "$SESSION_ID" --arg cwd "$CWD" --arg now "$NOW" --argjson d "$DISPATCHES" '
  def nofloat: (. * 10000000000 | round) / 10000000000;
  ($d | [.[].models] ) as $allm |
  ([ $allm[] | to_entries[] ] | group_by(.key) | map({
     key: .[0].key,
     value: {
       input_tokens: (map(.value.input_tokens)|add),
       output_tokens: (map(.value.output_tokens)|add),
       cache_write_5m_tokens: (map(.value.cache_write_5m_tokens)|add),
       cache_write_1h_tokens: (map(.value.cache_write_1h_tokens)|add),
       cache_read_tokens: (map(.value.cache_read_tokens)|add),
       cost_usd: (map(.value.cost_usd)|add|nofloat)
     }
   }) | from_entries) as $tm |
  { version:1, session_id:$sid, cwd:$cwd, updated_at:$now, status:"ok",
    dispatches:$d,
    totals: {
      models: $tm,
      cost_usd: ([ $tm[].cost_usd ] | add // 0 | nofloat),
      web_search_requests: ([ $d[].web_search_requests ] | add // 0),
      web_fetch_requests: ([ $d[].web_fetch_requests ] | add // 0)
    } }')"
printf '%s' "$DOC" > "$COST_FILE"
exit 0
