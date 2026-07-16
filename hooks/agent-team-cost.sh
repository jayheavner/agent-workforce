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
# Telemetry (2026-07-13 spec §2): the dispatch's per-call model override, when
# the orchestrator passed one. Stored raw on the fired dispatch's entry only;
# absent/garbage -> null. Additive bookkeeping — no pricing rule reads it.
REQ_MODEL="$(printf '%s' "$INPUT" | jq -r '.tool_input.model // empty')"

# Cannot even locate a cost file safely -> write nothing, exit 0.
[ -n "$SESSION_ID" ] || exit 0
[ -n "$TRANSCRIPT" ] || exit 0

# Path-confinement defense (Amendment 2026-07-09): session_id must be a UUID
# before it is used to build the cost-file name. Claude Code always supplies one.
case "$SESSION_ID" in
  [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]-[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) : ;;
  *) exit 0 ;;
esac

HERE="$(cd "$(dirname "$0")" && pwd)"
RATES="${AGENT_TEAM_RATES:-$HERE/model-rates.json}"
COST_DIR="${AGENT_TEAM_COST_DIR:-$HOME/.claude/logs/agent-team-cost}"
SUBAGENTS_DIR="${TRANSCRIPT%.jsonl}/subagents"
SLUG="$(printf '%s' "$CWD" | tr '/' '-')"
COST_FILE="$COST_DIR/$SLUG--$SESSION_ID.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
mkdir -p "$COST_DIR"

# Sticky unavailable: once a session's totals CANNOT BE TRUSTED (genuine
# structural corruption), they stay that way — a prior "unavailable" wins over
# any later good data. "partial" is deliberately NOT sticky: its numbers are
# exact for what was priceable, and a later fire (e.g. after a missing rate is
# added to model-rates.json) must be free to re-price and improve it to "ok".
if [ -f "$COST_FILE" ] && jq -e '.status? == "unavailable"' "$COST_FILE" >/dev/null 2>&1; then
  exit 0
fi

# write_unavailable REASON -> sticky marker, exit 0.
write_unavailable() {
  printf '%s' "$(jq -n --arg sid "$SESSION_ID" --arg cwd "$CWD" --arg now "$NOW" --arg r "$1" \
    '{version:1, session_id:$sid, cwd:$cwd, updated_at:$now, status:"unavailable", unavailable_reason:$r}')" \
    > "$COST_FILE"
  exit 0
}

# Load rates; unreadable/invalid rates -> unavailable.
jq empty "$RATES" 2>/dev/null || write_unavailable "rates file $RATES is missing or not JSON"

# is_transient_partial FILE -> exit 0 if the file looks like it is still being
# written (so it must be SKIPPED this fire and left for a later fire), exit 1
# otherwise. Two transient signatures (Amendment 2026-07-09, spec Component 1
# step 5): a 0-byte file; OR a non-empty file whose FINAL line fails to parse as
# JSON while EVERY preceding line parses as a JSON object (the mid-write tail).
# Any other parse failure is a genuine unrecognizable file (handled by
# parse_dispatch -> write_unavailable), not transient.
is_transient_partial() { # $1 file
  local file="$1"
  [ -s "$file" ] || return 0                      # 0-byte -> transient
  # If the whole file already parses, it is not partial.
  if jq -e . "$file" >/dev/null 2>&1; then return 1; fi
  # File has a parse failure somewhere. Transient only if it is confined to an
  # unterminated final line: all-but-last lines parse AND the last line does not.
  local total head_ok last_ok
  total="$(wc -l < "$file" | tr -d ' ')"          # count of NEWLINE chars
  # An unterminated tail means the byte stream does not end in a newline; the
  # "extra" trailing content is the (total+1)-th logical line. Validate the
  # first $total physical lines as a group, then the trailing remainder alone.
  head_ok=1; last_ok=1
  if [ "$total" -gt 0 ]; then
    head -n "$total" "$file" | jq -e . >/dev/null 2>&1 || head_ok=0
  fi
  # The trailing remainder after the last newline (empty if file ends in \n).
  tail -c +"$(( $(head -n "$total" "$file" | wc -c) + 1 ))" "$file" | jq -e . >/dev/null 2>&1 || last_ok=0
  # Transient iff the head parses cleanly and only the trailing remainder is bad.
  [ "$head_ok" -eq 1 ] && [ "$last_ok" -eq 0 ] && return 0
  return 1
}

# parse_dispatch FILE AGENT_TYPE -> prints the per-dispatch JSON object on
# stdout on success, or a one-line reason on stdout and a non-zero exit on any
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
    # Resolve each usage model to its priced family. The rates table is the sole
    # authority on known models: an id matches a key K when it equals K or begins
    # with "K-" (dated/variant releases like claude-haiku-4-5-20251001 -> the
    # claude-haiku-4-5 family), longest match winning. No assumption is made about
    # suffix shape, so a new dated id prices the day it ships with no code change;
    # adding a genuinely new family is a one-line rates edit. Unresolved ids pass
    # through verbatim and are tallied under unpriced_models (fail-open) below,
    # never blocking exact pricing of the priceable records.
    ($M | keys) as $KEYS |
    def canon:
      . as $id
      | ( [ $KEYS[] as $k | select($id == $k or ($id | startswith($k + "-"))) | $k ]
          | sort_by(length) | last ) as $match
      | ($match // $id);
    # Skip synthetic error model; strip trailing [1m]; canonicalize to rates key.
    [ $U[] | .m = (.message.model | sub("\\[1m\\]$";"") | canon) | select(.m != "<synthetic>") ] as $U2 |
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
    # Fail-open pricing (never estimate). An unpriceable model is NOT session-
    # fatal: its token counts are trustworthy, only its rate is missing. Split
    # logical requests into priceable and unpriceable; price the priceable ones
    # EXACTLY, tally the rest with NO cost field. The missing rate surfaces as
    # unpriced_models so adding it to model-rates.json re-prices EXACTLY on the
    # next fire — self-heal, no estimate anywhere. (Structural corruption is a
    # different failure: it errors above and pins the session sticky-unavailable,
    # because there the token numbers themselves cannot be trusted.)
    ( [ $reqs[] | select(.m | in($M)) ] ) as $preqs |
    ( [ $reqs[] | select(.m | in($M) | not) ] ) as $ureqs |
    # Price each priceable request by its date against std or intro rates.
    ( $preqs | map(
        ($M[.m]) as $mr |
        (if ($mr.intro != null) and (.ts[0:10] <= $mr.intro.ends) then $mr.intro else $mr end) as $r |
        . + { cost: ( (.input*$r.input + .output*$r.output + .cw5m*$r.cache_write_5m
                       + .cw1h*$r.cache_write_1h + .cread*$r.cache_read) / 1000000 ) }
      ) ) as $priced |
    # Aggregate priced per model (exact cost).
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
    # Aggregate unpriced per model: token counts ONLY, deliberately no cost field.
    ( $ureqs | group_by(.m) | map({
        key: .[0].m,
        value: {
          input_tokens: (map(.input)|add),
          output_tokens: (map(.output)|add),
          cache_write_5m_tokens: (map(.cw5m)|add),
          cache_write_1h_tokens: (map(.cw1h)|add),
          cache_read_tokens: (map(.cread)|add)
        }
      }) | from_entries ) as $unpriced |
    # server_tool_use tallies (billed per use, counted not priced).
    ( [ $U[] | .message.usage.server_tool_use.web_search_requests // 0 ] | add // 0 ) as $ws |
    ( [ $U[] | .message.usage.server_tool_use.web_fetch_requests // 0 ] | add // 0 ) as $wf |
    ( { agent_type: $atype, file: $file, file_size: $size,
        requests: ($reqs|length), models: $bymodel,
        web_search_requests: $ws, web_fetch_requests: $wf }
      + (if ($unpriced|length) > 0 then { unpriced_models: $unpriced } else {} end) )
    end end end
  '
}

# Load prior entries if the existing file is a valid "ok" OR "partial" doc; a
# sticky "unavailable" file is handled earlier (Task 6). Missing/invalid -> fresh.
# "partial" entries are reusable too, but any entry that still carries
# unpriced_models is re-parsed below (never reused) so a newly-added rate heals it.
PRIOR='{}'
if [ -f "$COST_FILE" ] && jq -e '.status=="ok" or .status=="partial"' "$COST_FILE" >/dev/null 2>&1; then
  PRIOR="$(jq -c '.dispatches // {}' "$COST_FILE")"
fi

# Scan the whole subagents dir every fire (D4: not just the just-fired
# dispatch) so an earlier dispatch's cost is never missing from the totals.
# Incremental rule: a dispatch file whose byte size matches its recorded
# entry is reused unchanged; new or size-changed files are (re)parsed in
# full and their entry replaced (D7 self-heal — never merged/appended).
DISPATCHES='{}'
if [ -d "$SUBAGENTS_DIR" ]; then
  for f in "$SUBAGENTS_DIR"/agent-*.jsonl; do
    [ -e "$f" ] || continue
    if is_transient_partial "$f"; then continue; fi   # still being written -> skip this fire
    aid="$(basename "$f")"; aid="${aid#agent-}"; aid="${aid%.jsonl}"
    size="$(wc -c < "$f" | tr -d ' ')"
    prior_size="$(printf '%s' "$PRIOR" | jq -r --arg k "$aid" '.[$k].file_size // "none"')"
    # A prior entry that still carries unpriced_models is never reused on file-size
    # match alone: its pricing depends on the rates config, which may have gained
    # the missing rate since. Re-parse it so the added rate heals it to exact.
    prior_unpriced="$(printf '%s' "$PRIOR" | jq -r --arg k "$aid" '(.[$k] // {}) | has("unpriced_models")')"
    if [ "$prior_size" = "$size" ] && [ "$prior_unpriced" != "true" ]; then
      entry="$(printf '%s' "$PRIOR" | jq -c --arg k "$aid" '.[$k]')"   # reuse unchanged
    else
      atype="unknown"; [ "$aid" = "$AGENT_ID" ] && atype="$AGENT_TYPE"
      entry="$(parse_dispatch "$f" "$atype")" || write_unavailable "$(basename "$f"): $entry"
      if printf '%s' "$entry" | jq -e '.error' >/dev/null 2>&1; then
        write_unavailable "$(basename "$f"): $(printf '%s' "$entry" | jq -r .error)"
      fi
    fi
    # requested_override: the fired dispatch takes this fire's value; every
    # other entry keeps whatever an earlier fire recorded (null when none).
    if [ "$aid" = "$AGENT_ID" ]; then
      entry="$(printf '%s' "$entry" | jq -c --arg m "$REQ_MODEL" \
        '. + {requested_override: (if $m == "" then null else $m end)}')"
    else
      prior_ov="$(printf '%s' "$PRIOR" | jq -c --arg k "$aid" '.[$k].requested_override // null')"
      entry="$(printf '%s' "$entry" | jq -c --argjson ov "$prior_ov" '. + {requested_override: $ov}')"
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
  # Session-level unpriced roll-up (token counts only, never a cost). Present iff
  # some dispatch had a model with no rate. Its existence flips status to
  # "partial": the priced totals above are EXACT, and these tokens are the exact
  # amounts awaiting a rate — no estimate is ever emitted for them.
  ([ $d[] | (.unpriced_models // {}) | to_entries[] ] | group_by(.key) | map({
     key: .[0].key,
     value: {
       input_tokens: (map(.value.input_tokens)|add),
       output_tokens: (map(.value.output_tokens)|add),
       cache_write_5m_tokens: (map(.value.cache_write_5m_tokens)|add),
       cache_write_1h_tokens: (map(.value.cache_write_1h_tokens)|add),
       cache_read_tokens: (map(.value.cache_read_tokens)|add)
     }
   }) | from_entries) as $um |
  ($um | length > 0) as $has_unpriced |
  ( { version:1, session_id:$sid, cwd:$cwd, updated_at:$now,
      status: (if $has_unpriced then "partial" else "ok" end),
      dispatches:$d,
      totals: {
        models: $tm,
        cost_usd: ([ $tm[].cost_usd ] | add // 0 | nofloat),
        web_search_requests: ([ $d[].web_search_requests ] | add // 0),
        web_fetch_requests: ([ $d[].web_fetch_requests ] | add // 0)
      } }
    + (if $has_unpriced then { unpriced_models: $um } else {} end) )')"
printf '%s' "$DOC" > "$COST_FILE"
exit 0
