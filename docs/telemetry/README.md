# Dispatch telemetry records

Machine-written model-routing telemetry: one JSONL file per session, one record per
subagent dispatch. No model, dispatch, or memory step is involved in producing it —
the closeout Stop hook (`hooks/agent_team_closeout.py`) runs
`hooks/cost_report.py --telemetry-dir` on the final, passing stop of any session that
dispatched work, and every field is computed from the session's transcripts.

Filename: `<cwd-slug>--<session-id>.jsonl` — the session's project cwd with every `/`
replaced by `-`, then the session id. Records land in the **workforce-owned telemetry
dir** — `$AGENT_TEAM_TELEMETRY_DIR`, default `~/.claude/logs/agent-team-telemetry/` —
never inside the client project. (Until 2026-07-22 they were written into the client
repo's `docs/telemetry/`; that collided with a curated project directory of the same
name and made the closeout hook dirty trees that other hooks police. This directory
in the workforce repo now holds only this README.) The file is rewritten whole from
transcripts at closeout, so it is always the complete, deduplicated picture of that
session.

Spec context: `docs/superpowers/specs/2026-07-18-autonomy-first-redesign.md`
(mechanism 4, "Machine telemetry"). Query with `tools/agent-team-scoreboard.sh`.

## Schema

One JSON object per line, one line per subagent dispatch:

```json
{
  "agent_id": "a1b2c3",
  "role": "builder",
  "resolved_models": ["claude-sonnet-5"],
  "requests": 12,
  "tokens": {"input": 84120, "output": 9310, "cw5m": 41200, "cw1h": 0, "cread": 512000},
  "cost_usd": 0.734210,
  "session_id": "<uuid>"
}
```

- `agent_id` — the harness subagent id; joins to the session cost file and to the
  subagent transcript.
- `role` — the dispatched agent type, taken from the session cost file;
  `"unknown"` when the cost file could not attribute the dispatch.
- `resolved_models` — every model that actually served requests in the dispatch, as
  the harness reported them (sorted, deduplicated). Usually one entry; a mid-dispatch
  model change yields more.
- `requests` — logical API requests (usage snapshots deduplicated by message id).
- `tokens` — exact token totals: `input`, `output`, `cw5m` / `cw1h` (5-minute and
  1-hour cache writes), `cread` (cache reads).
- `cost_usd` — the dispatch's exact cost at list rates from `hooks/model-rates.json`.
  Tokens for a model with no rate entry are counted but contribute no cost — never an
  estimate.
- `session_id` — the session the dispatch belonged to.

There are no tier, sequence, or verdict fields. Those were remembered facts a dispatch
had to write down at the moment of maximum context exhaustion, and they were never
reliably written; everything recorded here is mechanical.

## What it is for

Model-routing calibration: which roles ran on which models at what cost, so a human
can recalibrate the roster's model pins and the orchestrator's downshift/upshift
habits. `tools/agent-team-scoreboard.sh <telemetry-dir>` aggregates to one row per
(role, model) with dispatch count and total cost, sorted by cost.

## Semantics

- **Derived data.** Every record is recomputable from the session transcripts, which
  remain the source of truth. Losing a telemetry file loses convenience, not evidence.
- **Best-effort.** The hook writes telemetry after closeout enforcement has passed and
  swallows its own failures. Nothing blocks, retries, or asks a human because a
  telemetry write failed or a directory was absent.
- **Never load-bearing.** Nothing reads these records automatically; changing a model
  pin is a human edit informed by the scoreboard.
