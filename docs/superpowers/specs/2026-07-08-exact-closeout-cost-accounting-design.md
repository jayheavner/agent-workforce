# Exact Closeout Cost Accounting — Design

**Date:** 2026-07-08
**Status:** Accepted 2026-07-08; implemented per docs/superpowers/plans/2026-07-08-exact-closeout-cost-accounting.md

> **Amendment 2026-07-09 (partial-read self-heal fix).** Code review found a contradiction between
> D7's promised self-heal and the implemented behavior. The hook re-scans the WHOLE subagents
> directory every fire and treats ANY sibling file that fails to parse as a hard recognition
> failure — writing the sticky `"unavailable"` marker. Combined with the sticky early-return, that
> means a single sibling dispatch file caught mid-write (a truncated, not-yet-newline-terminated
> final line, or a still-empty 0-byte file) permanently pins the whole session to `"unavailable"`
> and forces the estimate fallback — defeating the feature in exactly the concurrent/lagging case
> D7 says self-heal covers. The fix (specified in §D7 and Component 1 step 5 below, marked
> "Amendment 2026-07-09") DISTINGUISHES two failure modes at the point a sibling file fails to
> parse: a genuinely unrecognizable-but-complete file stays sticky-unavailable (unchanged); a
> file that is plausibly still being written is SKIPPED this fire and left for a later fire to
> pick up once flushing completes. This amendment also folds in three review nits, noted inline in
> Components 1, 5, and 6. No redesign; the two-path fallback, dedup, pricing, and schema are
> unchanged.
**Relation to existing spec:** This ships the follow-on that `2026-07-07-ai-agent-team-design.md`
§Scope explicitly deferred: "exact per-session cost accounting (a transcript-parsing PostToolUse
hook summing per-request input/output/cache usage — the closeout's estimate table is the shipped
v1)." That spec's Closeout cost report section and the README must be amended when this ships
(see Files to be changed).

## Problem

The orchestrator's final-gate cost table is an estimate: per-dispatch token totals from
background-completion notifications, multiplied by a blended per-model rate that assumes an
~85/15 input/output split and ignores cache discounts entirely. On cache-heavy agentic work the
blended estimate can be wrong by a large factor in either direction (cache reads cost 0.1x input;
cache writes cost 1.25x–2x input). The human's only exact number is `/usage`, which is
session-wide and not per-model or per-dispatch.

Every API request's exact usage — input, output, cache-write, and cache-read tokens, attributed
to a model — is already recorded on disk in the session transcripts. This design adds a
PostToolUse hook on the orchestrator that sums those records incrementally into a per-session
cost file, priced from a rates config, and teaches the orchestrator to emit an EXACT per-model
table at the final gate — falling back to the existing blended-estimate table whenever exact data
is absent or marked unavailable. The fallback is load-bearing: the hook must never produce a
wrong number; when in doubt it declares itself unavailable and the estimate table takes over.

## Discovery findings (verified 2026-07-08, with evidence)

Everything below was verified against the official Claude Code hooks documentation
(`code.claude.com/docs/en/hooks.md`), the locally tested hooks reference
(`~/.claude/skills/hook-architect/hooks-reference.md`, verified against Claude Code 2.1.119), and
real transcripts on disk under `~/.claude/projects/` (Claude Code 2.1.202, including this repo's
own shakedown sessions). Nothing here is assumed.

### D1. PostToolUse hook payload

A PostToolUse `command` hook receives JSON on stdin. Confirmed fields (official hooks doc):

- Common to all events: `session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`,
  `effort`, `hook_event_name`, plus `agent_id`/`agent_type` when running inside a subagent.
- PostToolUse-specific: `tool_name`, `tool_input`, `tool_response`.
- `transcript_path` points at the session's JSONL conversation file. Documented caveat: "The
  transcript file is written asynchronously and may lag the in-memory conversation" — see D7.
- PostToolUse cannot block (the tool already ran); exit 0 = success, non-zero = non-blocking
  error noise. The hook must always exit 0.

The dispatch tool is named `Agent` in this setup — verified in the shakedown session's main
transcript (`~/.claude/projects/-Users-jay-claude-ai-agent-team/e41a4464-….jsonl` contains
`"name":"Agent"` tool_use blocks, lines 49 and 100), matching the orchestrator frontmatter's
`Agent(architect)` tool grants. The hook matcher is therefore `Agent`.

The `tool_response` for a completed Agent dispatch (observed as `toolUseResult` in the main
transcript, line 50 of the session above) carries `agentId` (e.g. `"a903a11b800810642"`),
`agentType`, `resolvedModel` (e.g. `"claude-opus-4-8[1m]"`), `totalDurationMs`, `totalTokens`,
`totalToolUseCount`, and a `usage` object. **Critical negative finding:** that `usage` object
covers only the final API iteration of the dispatch, not the whole run — in the observed
dispatch, `totalTokens: 46880` equals exactly the final request's `2 + 1291 + 41888 + 3699`
(input + cache-write + cache-read + output), while the dispatch's own transcript file contains
many additional requests whose usage is not included. So `tool_response.usage` **cannot** be the
source of exact totals; only the transcript files can. `tool_response.agentId` is still useful:
it names the file to parse and labels it with `agentType`.

### D2. Transcript on-disk format

Transcripts are JSONL — one JSON object per line. Per-request usage lives on records with
`"type":"assistant"`. Full observed envelope (subagent file
`…/e41a4464-…/subagents/agent-a903a11b800810642.jsonl`, line 4):

```json
{"parentUuid":"…","isSidechain":true,"agentId":"a903a11b800810642",
 "message":{"model":"claude-opus-4-8","id":"msg_011CcoH5xCDQM1GAz8p3Fv1i","type":"message",
   "role":"assistant","content":[…],
   "usage":{"input_tokens":9465,"cache_creation_input_tokens":7389,
            "cache_read_input_tokens":0,
            "cache_creation":{"ephemeral_5m_input_tokens":7389,"ephemeral_1h_input_tokens":0},
            "output_tokens":4,"service_tier":"standard","inference_geo":"global"}},
 "requestId":"req_011CcoH5wEAsH1QhRLHm9ruQ","type":"assistant",
 "uuid":"…","timestamp":"2026-07-07T19:50:20.677Z","sessionId":"e41a4464-…","version":"2.1.202"}
```

Exact usage field names, confirmed: `input_tokens`, `output_tokens`,
`cache_creation_input_tokens`, `cache_read_input_tokens`, and a `cache_creation` sub-object
splitting the write into `ephemeral_5m_input_tokens` / `ephemeral_1h_input_tokens` (the 5m/1h
split matters because the two TTLs have different prices; observed sessions always show 1h = 0).
Model attribution is per record at `.message.model`, as a bare model ID (`claude-opus-4-8`,
`claude-sonnet-5`, …) — a grep across the whole project directory found **zero** occurrences of
a `[1m]`-suffixed value in `.message.model` (the suffix appears only in the Agent tool result's
`resolvedModel`), but the hook strips a trailing `[1m]` defensively before rate lookup.

### D3. Duplicate usage snapshots — dedup is mandatory

One API request produces **multiple** JSONL lines (one per content block / streaming snapshot),
each repeating the same `message.id`, `requestId`, and usage object. Observed (same file):
lines 7, 8, 10, 12, 14 all carry `msg_011CcoH6Ns31JxQgk9JbK49E` with identical
`input_tokens:778, cache_creation:16394, cache_read:7389`; only the **last** line carries the
final `output_tokens:1210` (earlier snapshots carry a smaller interim value or omit the field).
Naively summing per line would multiply input/cache token counts several-fold.

Dedup rule derived from this evidence: group assistant records by `.message.id`; within a group
the input and cache fields must be identical across snapshots (verified property; treated as a
format-recognition check), and `output_tokens` is the **maximum** across the group's snapshots
(missing = 0).

### D4. CRITICAL — subagent usage is in SEPARATE files, not the main transcript

Subagent (sidechain) transcripts live in sibling files:
`~/.claude/projects/<project-slug>/<session-id>/subagents/agent-<agentId>.jsonl` — one file per
dispatch, `agentId` matching `tool_response.agentId`. Evidence, from this repo's own shakedown
session `e41a4464-ba82-4494-8a7f-4637836069fe`:

- The main transcript `e41a4464-….jsonl` contains **zero** records with `"isSidechain":true`
  (grep count: 0). Its 87 `usage` occurrences are all the orchestrator's own requests.
- The directory `e41a4464-…/subagents/` exists with one `agent-*.jsonl` per dispatch; every
  record in those files has `"isSidechain":true`, `"agentId":"<id>"`, and `sessionId` equal to
  the MAIN session id.
- The same layout holds across every other project checked under `~/.claude/projects/`
  (1,363 `.jsonl` files scanned; `subagents/` subdirectories throughout).

Consequence: the hook cannot sum everything from `transcript_path` alone. It derives the
subagents directory from the payload — `transcript_path` minus its `.jsonl` extension, plus
`/subagents` — and sums the per-dispatch files there. Conveniently, this makes the incremental
design natural: one dispatch = one file, complete (modulo D7 lag) when that dispatch's
PostToolUse fires.

### D5. jq availability and the existing hook's stdin pattern

`install.sh` line 14 hard-fails without jq (`command -v jq >/dev/null 2>&1 || fail "jq is
required"`), and the existing policy hook consumes stdin exactly as this hook will:
`INPUT="$(cat)"` then `jq -r '.tool_name // empty'` etc. (`hooks/agent-team-policy.sh` lines
12–13). The policy hook runs in production (the audit log exists), so jq is present and the
pattern is proven. The new hook follows the same conventions: `#!/usr/bin/env bash`, `set -u`,
stdin slurped once, jq for all JSON work, env-var override for its output location (mirroring
`AGENT_TEAM_AUDIT_LOG`), and resolution of sibling files via
`"$(cd "$(dirname "$0")" && pwd)"` so the installed copy under `~/.claude/hooks/` finds the
installed rates file.

### D6. Hook registration convention

Hooks in this repo are registered in agent frontmatter, not in `settings.json`
(`agents/builder.md` lines 9–18 register PreToolUse matchers; the repo deliberately keeps
`~/.claude/settings.json` untouched — the doc-inventory hooks were unregistered from it on
2026-07-02 per project CLAUDE.md). The new hook is registered in `agents/orchestrator.md`
frontmatter as `PostToolUse` / matcher `Agent`. The orchestrator runs as the main session
(`claude --agent orchestrator`), and agent-frontmatter hooks apply to the session running that
agent. Residual risk (frontmatter PostToolUse not firing for a main-session agent in some client
version) is absorbed by design: no cost file → the closeout falls back to the estimate table,
which is acceptance criterion 3.

### D7. Transcript write lag

The hooks doc warns the transcript file may lag the in-memory conversation when a hook fires.
For this design the exposure is small — the hook reads per-dispatch files that were finished
before the *current* dispatch's completion event — but a sibling dispatch file (or the
last-completed dispatch's own file) could in principle still be flushing when a fire scans the
whole directory. Mitigations: (a) every fire re-scans **all** dispatch files and re-sums any
whose byte size changed; (b) in the standard route a scribe status-note dispatch follows the last
work dispatch before the final gate, providing a later fire in practice.

> **Amendment 2026-07-09 — self-heal now actually works.** The original text claimed "any later
> fire self-heals earlier partial reads." That was only true if the partial read did not trip the
> sticky marker — but it did: the whole-file `jq -e .` parse fails on a truncated final line, the
> hook wrote sticky `"unavailable"`, and the sticky early-return then blocked every later fire from
> ever re-scanning. A transient timing artifact permanently pinned the session. Correction: the
> hook now DISTINGUISHES a **transient partial read** from a **genuine unrecognizable file** (see
> Component 1 step 5, Amendment 2026-07-09) and, for the transient case, SKIPS that one file this
> fire WITHOUT writing the sticky marker — so a later fire, once the file has finished flushing,
> picks it up and prices it. Discriminator: a **0-byte file**, OR a file whose **final line is not
> newline-terminated / does not parse as JSON while every preceding line parses**, is treated as
> "still being written" → skip this fire, leave for later. Any other parse failure (a fully-written
> non-JSON line anywhere but the unterminated tail, a shape/dedup/split violation, a model absent
> from rates) remains a genuine unrecognizable file → sticky `"unavailable"`, as before. With this
> fix the self-heal claim is true: the good dispatches price correctly now, and the transient file
> is folded in on the next fire.

### D8. Rates (list prices, verified against the claude-api reference, cached 2026-06-24/07)

Per million tokens, USD. Cache-write = input x1.25 (5-minute TTL) or x2 (1-hour TTL); cache-read
= input x0.1 — verified ratios from the same reference.

| Model | Input | Output | Cache write 5m | Cache write 1h | Cache read |
|---|---|---|---|---|---|
| claude-haiku-4-5 | 1.00 | 5.00 | 1.25 | 2.00 | 0.10 |
| claude-sonnet-5 | 3.00 | 15.00 | 3.75 | 6.00 | 0.30 |
| claude-sonnet-5 (intro, through 2026-08-31) | 2.00 | 10.00 | 2.50 | 4.00 | 0.20 |
| claude-opus-4-8 | 5.00 | 25.00 | 6.25 | 10.00 | 0.50 |
| claude-fable-5 | 10.00 | 50.00 | 12.50 | 20.00 | 1.00 |

Opus 4.8 has **no long-context premium** (verified: "1M context window at standard API pricing");
no long-context premium is documented for the other team models either, so the rates model is
flat per model. If tiered pricing ever appears, it is a rates-file schema extension, not a code
assumption to unwind. These numbers live only in `hooks/model-rates.json` — never in the script.

## Design

### Alternatives considered

1. **Sum `tool_response.usage` per dispatch (no transcript parsing).** Rejected: D1 shows that
   object covers only the dispatch's final API iteration — it would silently under-report, which
   violates the never-a-wrong-number rule.
2. **One incremental byte-offset parser over the main transcript.** Rejected: D4 shows subagent
   usage never appears there; and offset-tracking across streaming duplicate snapshots (D3)
   would need per-message running state to avoid double counting.
3. **Stop/SessionEnd hook.** Rejected: fires too late — the final gate needs current data while
   the session is still running, and per-dispatch attribution would be lost.
4. **Chosen: PostToolUse(Agent) hook + per-dispatch-file accounting.** Each dispatch's usage is
   a small, self-contained file named by `agentId`. Incrementality falls out at file
   granularity: parse each file once, re-parse only if its size changed, never re-parse
   unchanged files. No offsets, no cross-file dedup state.

### Component 1 — `hooks/agent-team-cost.sh` (new)

Registered in `agents/orchestrator.md` frontmatter:

```yaml
hooks:
  PostToolUse:
    - matcher: Agent
      hooks:
        - type: command
          command: "$HOME/.claude/hooks/agent-team-cost.sh"
```

Behavior per fire (always exits 0, whatever happens):

1. Slurp stdin; extract `session_id`, `transcript_path`, `cwd`, `tool_response.agentId`,
   `tool_response.agentType` via jq. Missing `session_id` or `transcript_path` → write nothing,
   exit 0 (cannot even locate a cost file safely).

   > **Amendment 2026-07-09 (nit 3 — path-confinement defense).** Before constructing the cost-file
   > path, sanity-check `session_id` against the UUID shape
   > (`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`). A
   > `session_id` that does not match ⇒ write nothing, exit 0 (defense-in-depth against a
   > path-traversal or unexpected value slipping into the filename; Claude Code always supplies a
   > UUID here). This is in addition to the existing non-empty check.
2. Resolve paths. Subagents dir = `transcript_path` with the trailing `.jsonl` removed, plus
   `/subagents`. Cost file = `$AGENT_TEAM_COST_DIR/<cwd-slug>--<session_id>.json`, where
   `AGENT_TEAM_COST_DIR` defaults to `$HOME/.claude/logs/agent-team-cost` (env override exists
   for tests, mirroring `AGENT_TEAM_AUDIT_LOG`) and `<cwd-slug>` is `cwd` with every `/`
   replaced by `-` (the same encoding Claude Code uses for project directories). Rates file =
   `model-rates.json` in the script's own directory (dirname-of-$0 resolution, like the policy
   hook sources its lib), overridable via `AGENT_TEAM_RATES` for tests.
3. Load the existing cost file if present and parseable; otherwise start fresh. A cost file
   already marked `"status":"unavailable"` stays unavailable — the marker is sticky for the
   session (once any dispatch was unparseable, the session's exact totals can't be trusted).
4. Scan `subagents/agent-*.jsonl`. For each file: if the cost file already has an entry for
   that `agentId` with the same recorded `file_size`, skip it (this is the incremental rule).
   New or size-changed files are (re)parsed in full and their entry **replaced** — replacement,
   not addition, makes every fire idempotent and self-healing (D7). A missing subagents
   directory with no prior entries is a valid empty state, not an error.
5. Parse one dispatch file (all in jq, one pass per file):

   > **Amendment 2026-07-09 — transient-partial pre-check (runs BEFORE recognition below).**
   > Before applying the recognition rules, classify the file:
   > - **0-byte file** ⇒ transient (still being created) ⇒ **SKIP this file this fire**: do not
   >   count it, do not write the sticky marker, leave no entry for it. A later fire picks it up.
   > - **Non-empty file whose FINAL line fails to parse as JSON while every PRECEDING line parses
   >   as a JSON object** (the signature of a mid-write, not-yet-newline-terminated tail) ⇒
   >   transient ⇒ **SKIP this file this fire** (same as above).
   > - **Any other parse failure** — a non-JSON line that is NOT the sole unterminated tail (e.g. a
   >   fully-written garbage line with valid lines after it), or all recognition failures b–e below
   >   ⇒ **genuine unrecognizable file** ⇒ sticky unavailable marker, exit 0 (unchanged behavior).
   >
   > Rationale: a file being flushed can only ever have its incompleteness at the tail; a defect in
   > the middle with good lines after it means the writer already moved past that point, so it is a
   > real corruption, not a timing artifact. Skipping (not marking) the transient case is what makes
   > the D7 self-heal promise true — see §D7 Amendment 2026-07-09.
   >
   > **Accepted ambiguity (derivable trade, not a wrong number).** An unterminated final bad line is
   > indistinguishable from a mid-flush truncation — both present as "valid head, unparseable
   > trailing remainder." This discriminator deliberately resolves that ambiguity toward *transient*
   > (skip and retry) rather than *sticky*. The safety argument holds either way: if the tail was a
   > real, permanent corruption that never completes, that one dispatch is simply **never counted** —
   > a *missing* figure, never a *wrong* one — and the exact table it feeds is only ever emitted at
   > the final gate after the writing dispatch has completed (by which point a genuine record is
   > newline-terminated and parses, while a truly corrupt tail stays skipped). The never-a-wrong-number
   > invariant is preserved; only the "one bad tail poisons the whole session" over-reach is removed.
   > A corruption anywhere but the sole unterminated tail is unambiguous and still goes sticky.

   - Format recognition — ALL of the following, else the whole cost file is rewritten as the
     unavailable marker (see below) and the hook exits 0:
     a. every line parses as a JSON object (subject to the transient pre-check above: a sole
        unterminated final line does not trip this rule — it triggers the skip);
     b. every record with `.type == "assistant"` and non-null `.message.usage` has a string
        `.message.id`, a non-empty string `.message.model`, and numeric
        `.usage.input_tokens`, `.usage.cache_creation_input_tokens`,
        `.usage.cache_read_input_tokens` (`output_tokens` may be absent on interim snapshots);
     c. within each `.message.id` group, input and cache fields are identical across snapshots
        (D3 invariant);
     d. when `.usage.cache_creation` is present, `ephemeral_5m_input_tokens +
        ephemeral_1h_input_tokens == cache_creation_input_tokens`; when absent, the whole write
        is attributed to the 5m tier (the Claude Code default; observed 1h is always 0);
     e. every model seen (after stripping a trailing `[1m]`, and excluding the synthetic
        error-message model `<synthetic>`, whose records are skipped) has an entry in the rates
        config.
   - Dedup and sum: one logical request per `.message.id`; per model, sum the five token
     classes (input, output, cache-write-5m, cache-write-1h, cache-read).
   - Price: each request is priced by its record `timestamp` — if the model's rates entry has an
     `intro` block and the timestamp date is on or before `intro.ends`, intro rates apply,
     otherwise standard rates. Cost per request = sum(class tokens x class rate) / 1,000,000.
     Costs accumulate at full floating-point precision; rounding to cents happens only at
     display time.
   - Also tally `server_tool_use.web_search_requests` / `web_fetch_requests` when present.
     These are billed per-use, not per-token; rather than guessing a price, the cost file
     carries the counts and the closeout table footnotes any nonzero count as unpriced. Token
     figures stay exact; nothing is invented.
6. Label the entry: the `agentId` from this fire's `tool_response` gets its `agentType`
   recorded; files discovered only by scan keep their previous label or `"unknown"`.
7. Recompute per-model and grand totals across all dispatch entries; write the whole cost file
   in one `printf '%s'` redirect of a jq-built document (no temp file + `mv` — the repo's
   no-move discipline applies, and a single-shot write of a small file is sufficient; the
   orchestrator treats an unparseable file as absent).

> **Amendment 2026-07-09 (nit 1 — comment accuracy).** The implemented `parse_dispatch` header
> comment says failures print the reason "on stderr"; the code actually prints the reason on
> **stdout**, and the scan loop relies on capturing it there (`entry="$(parse_dispatch …)"`). The
> code is correct; the comment is wrong. Fix the comment to say stdout — do not change the code.

**Unavailable-marker semantics.** On any recognition failure (step 5a–e, excluding the
transient-partial cases which are skipped not marked — Amendment 2026-07-09 above), on an
unreadable rates file, or on any internal jq error, the hook writes the cost file as:

```json
{"version": 1, "session_id": "…", "cwd": "…", "updated_at": "…",
 "status": "unavailable",
 "unavailable_reason": "agent-a1b2….jsonl: unparseable line 17"}
```

and exits 0. It never writes partial or guessed numbers, never exits non-zero, and the marker is
sticky for the session. The orchestrator treats `status != "ok"` — and equally a missing or
unreadable file — as "no exact data": fall back to the estimate table.

### Component 2 — `hooks/model-rates.json` (new)

All prices are USD per million tokens; list prices as of the `as_of` date. Editing this file
(plus reinstall) is the only way rates change — the script contains no numbers.

```json
{
  "comment": "USD per million tokens. Source: Anthropic list prices. Edit + reinstall to change.",
  "as_of": "2026-07-08",
  "models": {
    "claude-haiku-4-5": { "input": 1.00, "output": 5.00,
      "cache_write_5m": 1.25, "cache_write_1h": 2.00, "cache_read": 0.10 },
    "claude-sonnet-5": { "input": 3.00, "output": 15.00,
      "cache_write_5m": 3.75, "cache_write_1h": 6.00, "cache_read": 0.30,
      "intro": { "ends": "2026-08-31",
        "input": 2.00, "output": 10.00,
        "cache_write_5m": 2.50, "cache_write_1h": 4.00, "cache_read": 0.20 } },
    "claude-opus-4-8": { "input": 5.00, "output": 25.00,
      "cache_write_5m": 6.25, "cache_write_1h": 10.00, "cache_read": 0.50 },
    "claude-fable-5": { "input": 10.00, "output": 50.00,
      "cache_write_5m": 12.50, "cache_write_1h": 20.00, "cache_read": 1.00 }
  }
}
```

Schema rules: every model entry must carry all five rate keys (numbers); `intro` is optional and,
when present, carries `ends` (ISO date) plus the same five keys. `claude-haiku-4-5` is included
because the orchestrator downshifts researcher/scribe/ticketer/verifier dispatches to Haiku. A
model missing from this file that appears in a transcript with usage → unavailable marker (spec
rule 5e), which is the loud-failure path for future model additions.

### Component 3 — per-session cost file schema

`~/.claude/logs/agent-team-cost/<cwd-slug>--<session_id>.json`:

```json
{
  "version": 1,
  "session_id": "e41a4464-ba82-4494-8a7f-4637836069fe",
  "cwd": "/Users/jay/claude/csv2json-2",
  "updated_at": "2026-07-08T21:14:03Z",
  "status": "ok",
  "dispatches": {
    "a903a11b800810642": {
      "agent_type": "architect",
      "file": "/Users/jay/.claude/projects/…/subagents/agent-a903a11b800810642.jsonl",
      "file_size": 184223,
      "requests": 14,
      "models": {
        "claude-opus-4-8": {
          "input_tokens": 1211, "output_tokens": 6418,
          "cache_write_5m_tokens": 52840, "cache_write_1h_tokens": 0,
          "cache_read_tokens": 391220,
          "cost_usd": 0.6864
        }
      },
      "web_search_requests": 0, "web_fetch_requests": 0
    }
  },
  "totals": {
    "models": {
      "claude-opus-4-8": {
        "input_tokens": 1211, "output_tokens": 6418,
        "cache_write_5m_tokens": 52840, "cache_write_1h_tokens": 0,
        "cache_read_tokens": 391220,
        "cost_usd": 0.6864
      }
    },
    "cost_usd": 0.6864,
    "web_search_requests": 0, "web_fetch_requests": 0
  }
}
```

When `status` is `"unavailable"`, `dispatches`/`totals` are omitted and `unavailable_reason` is
present (see Component 1). `file_size` is the incremental bookkeeping key; `cost_usd` values are
unrounded floats.

### Component 4 — orchestrator closeout changes (`agents/orchestrator.md`)

The frontmatter gains the hooks block (Component 1). The "Closeout cost report" section is
rewritten to a two-path procedure:

1. **Exact path.** At the FINAL gate only: Glob
   `~/.claude/logs/agent-team-cost/<own-cwd-slugged>--*.json` (the orchestrator knows its own
   cwd; slug = `/` → `-`), Read the most recently modified match, and if it parses with
   `"status":"ok"`, emit the EXACT table: one row per model with input, output, cache-write
   (5m+1h combined), and cache-read token totals plus cost rounded to the cent, a grand-total
   row, and — when available in its own dispatch log — the per-dispatch agent/model attribution
   it already tracks. Label: exact per-request figures from session transcripts, priced at list
   rates from `model-rates.json`; excludes the orchestrator's own session usage (that remains
   `/usage`); footnote any nonzero unpriced web-search/web-fetch counts.
2. **Fallback path.** If no file matches, the file doesn't parse, or `status` is not `"ok"`:
   emit the existing blended-estimate table, unchanged, with its existing estimate labeling.
   The blended-rate table stays in `agents/orchestrator.md` for exactly this purpose.

Rounding rule for display: round half away from zero to two decimals (jq: `(. * 100 | round) /
100`). Known limitation, documented in the section: two concurrent orchestrator sessions in the
same project directory share the Glob pattern; most-recent-file wins.

### Component 5 — tests (`tests/test_cost_hook.sh` + `tests/fixtures/cost/`, new)

Fixture-driven, following `tests/test_policy_hooks.sh` exactly: a `run_hook` helper feeds a
crafted stdin payload to `bash hooks/agent-team-cost.sh` with `AGENT_TEAM_COST_DIR` and
`AGENT_TEAM_RATES` pointed at a `mktemp -d` scratch area, `expect`-style assertions increment
PASS/FAIL, final line `passed=N failed=M`, exit non-zero on any failure.

Fixtures (committed files under `tests/fixtures/cost/`, laid out as a fake project directory:
`<sid>.jsonl` main transcript plus `<sid>/subagents/agent-*.jsonl`):

- **Good fixture**: two dispatch files, two models total, including (a) duplicate streaming
  snapshots of one message id with identical input/cache and growing `output_tokens` — exercises
  dedup; (b) a `cache_creation` 5m/1h split record; (c) one `claude-sonnet-5` record timestamped
  before `intro.ends` and one after — exercises date-dependent pricing. Token values are chosen
  so hand-computed per-model costs are exact at four decimal places.
- **Malformed fixture**: a dispatch file with a non-JSON line.
- **Unknown-model fixture**: a valid file whose `.message.model` is absent from the test rates
  file.

Required cases:

1. Good fixture, single fire → cost file `status:"ok"`; every per-model token class and
   `cost_usd` equals the hand-computed value exactly (the hand math is written in comments in
   the test file, per the policy-test convention of executable spec).
2. Same fire repeated → byte-identical totals (idempotency / no double count).
3. Append one more complete request to a copy of a dispatch fixture (grow the file) → re-run →
   totals update to the new hand-computed values (size-based invalidation works).
4. Malformed fixture → cost file has `status:"unavailable"` with a reason, and the hook exit
   code is 0.
5. Unknown-model fixture → same as case 4.
6. Unavailable is sticky: after case 4, a subsequent fire over good files alone leaves
   `status:"unavailable"`.
7. Existing `tests/test_policy_hooks.sh` still passes untouched (regression).

### Component 6 — installer changes (`install.sh`)

Following the existing validate → back up → install → rollback pattern, symmetric with the
policy-hook files:

- Validation (before anything is touched): `bash -n hooks/agent-team-cost.sh`;
  `jq empty hooks/model-rates.json` **and** a shape check that every entry under `.models` has
  the five numeric rate keys (loud failure beats a silently unpriceable rates file);
  `bash tests/test_cost_hook.sh >/dev/null` alongside the policy tests.

  > **Amendment 2026-07-09 (nit 2 — rate-precision guard).** Extend the shape check so it also
  > fails loudly if any rate value under `.models` (including the `intro` block) has **more than 4
  > fractional decimal digits**. This protects the hook's `nofloat` 10-decimal snap invariant,
  > which is only safe today because every list rate has ≤2 decimals; a future rate like
  > `2.123456789` could push a computed cost past the point where the 10-decimal snap removes only
  > IEEE-754 artifact noise. A rate carrying >4 fractional digits is almost certainly a typo, so
  > failing the installer is the right loud response. The guard belongs with the existing
  > `jq -e` rate-shape check; add/adjust an installer-check test if the test pattern covers it.
- Backup/restore/cleanup-fresh handling for `~/.claude/hooks/agent-team-cost.sh` and
  `~/.claude/hooks/model-rates.json`, mirroring `PREEXISTING_POLICY*`.
- Install: copy both; `chmod +x` the script (the rates file is only read). `mkdir -p` of
  `~/.claude/logs` already happens; the hook itself creates `agent-team-cost/` on first write.
- `agents/orchestrator.md` needs no installer change — the agent-copy loop already ships it.

## Files to be changed

| File | Change |
|---|---|
| `hooks/agent-team-cost.sh` | Create — the PostToolUse cost-accounting hook (Component 1) |
| `hooks/model-rates.json` | Create — rates config (Component 2) |
| `tests/test_cost_hook.sh` | Create — fixture-driven hook tests (Component 5) |
| `tests/fixtures/cost/…` | Create — good / malformed / unknown-model transcript fixtures |
| `agents/orchestrator.md` | Modify — frontmatter hooks block; rewrite Closeout cost report section (Component 4), keeping the blended table as fallback |
| `install.sh` | Modify — validate + install the two new hook files, run the new test suite (Component 6) |
| `README.md` | Modify — closeout description (exact table + fallback), install validation list, a short "Cost accounting" section naming the log location and rates file |
| `docs/superpowers/specs/2026-07-07-ai-agent-team-design.md` | Modify — dated amendment note in "Closeout cost report" and "Scope — v1" pointing at this spec (the deferred item has shipped) |

No file is deleted, moved, or overwritten via shell in any step; all edits are in-place via
Edit/Write. No new packages: bash + jq only, both already required.

## Decisions resolved during design (with rationale)

- **Orchestrator's own session usage stays excluded from the exact table.** Parity with the
  estimate's existing scope; including it would require continuously re-parsing the growing main
  transcript on every fire (the exact design smell the constraints forbid); `/usage` already
  covers the human's session-wide exact number. Revisit only if the human asks for it.
- **Incrementality is at dispatch-file granularity, not byte offsets.** One dispatch = one
  small, immutable-once-complete file; "skip if size unchanged, re-parse and replace if grown"
  is simpler than offset bookkeeping and immune to the duplicate-snapshot problem at chunk
  boundaries (D3).
- **Unavailable is sticky per session.** A single unparseable dispatch means the session total
  would be a lie; partial-exact tables are wrong numbers wearing exact labels.
- **Server web-search/web-fetch requests are counted and footnoted, not priced.** Their per-use
  price was not verifiable from the consulted references; inventing one would violate the
  no-wrong-numbers rule, and dropping the count silently would too.
- **Cost file discovery via cwd-slug + newest match** rather than the orchestrator knowing its
  session id (it doesn't). Concurrent same-directory sessions are a documented limitation.

## Acceptance criteria

1. **Exact math:** running the hook over the committed good fixture produces per-model token
   classes and costs that match the hand computation in the test file to the cent (verbatim
   equality on the stored values), including the dedup, 5m/1h split, and intro-pricing cases.
2. **No wrong numbers:** the malformed and unknown-model fixtures each yield a cost file whose
   `status` is `"unavailable"` (with a reason) and a hook exit code of 0 — never partial totals.
3. **Idempotent and incremental:** re-firing over unchanged files changes nothing; growing a
   dispatch file updates exactly that dispatch's entry.
4. **Suites green:** `tests/test_policy_hooks.sh`, `tests/test_cost_hook.sh`, and
   `bash install.sh` all pass.
5. **Graceful fallback:** a session where the hook never ran (no cost file) still produces the
   existing blended-estimate closeout table — verified by the orchestrator.md wording (two-path
   procedure) and exercised in the next shakedown.

## Out of scope

Pricing server-tool web search/fetch (counted, footnoted); the orchestrator's own session usage;
automatic rate updates (rates change only by editing `model-rates.json` and reinstalling);
per-dispatch cost attribution beyond what the orchestrator already tracks from completion
notifications; any `settings.json` registration.
