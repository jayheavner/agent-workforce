# Dispatch telemetry records

One JSONL file per session, written by the scribe on the orchestrator's closeout
dispatch. Filename: `<project-slug>--<session-id>.jsonl` (the cost file's slug scheme:
the project cwd with every `/` replaced by `-`). One line per dispatch outcome record.

Spec: `docs/superpowers/specs/2026-07-13-dispatch-telemetry-design.md`. Query with
`tools/agent-team-scoreboard.sh` or the jq one-liner in the top-level README.

## Schema (v1)

```json
{
  "schema": 1,
  "logged_at": "2026-07-13T18:20:05Z",
  "session_id": "<uuid>",
  "project": "<cwd>",
  "task_slug": "<orchestrator-assigned>",
  "tier": "small | standard | large",
  "dispatch_id": "<agentId, joins to the cost file>",
  "role": "<one of the nine specialists>",
  "requested_model": "<see resolution order below, or null>",
  "resolved_model": "<harness-reported, from the cost file's model keys, or null>",
  "model_drift": "boolean, or null when either side is unknown",
  "sequence": "first | repair-1 | repair-2 | n/a",
  "verdict": "pass | fail | escalated | n/a",
  "framing": "claude-xml | gpt-markdown | outcome-first | unframed-fallback | n/a",
  "tokens": "number or null",
  "cost_usd": "number or null",
  "cost_available": "boolean"
}
```

`sequence` and `verdict` are populated only for builder and architect work dispatches
(the roles with a checker loop); every other role gets `n/a` on both. `first_try_pass`
is never stored — it is derived at query time as `sequence == "first" AND verdict == "pass"`.

`framing` records which dispatch envelope framing the orchestrator applied, per
`skills/agent-workforce/references/plan-formatting.md`. It is populated only for builder
work dispatches (the framing target); every other role gets `n/a`. Telemetry stays
best-effort: a missing framing label is written `n/a`, never guessed, and never blocks
closeout.

## `requested_model` resolution order

1. The dispatch's `requested_override` from the session cost file (the per-dispatch
   `model` parameter the orchestrator passed, captured by the cost hook).
2. Else the role's pin from `~/.claude/hooks/agent-model-defaults.json`.
3. Else `null` (and `model_drift` is then `null`, never guessed).

`model_drift` = normalized `requested_model` != normalized `resolved_model`
(normalization strips a trailing `[1m]`). Drift is surfaced, never credited: the
scoreboard buckets every record by `resolved_model`.

## Rules for the scribe

- Mechanical facts (`role`, `resolved_model`, `requested_override`, `tokens`,
  `cost_usd`) come from the session cost file, matched by `dispatch_id`. Verdict facts
  (`task_slug`, `tier`, `sequence`, `verdict`) come from the orchestrator's dispatch
  prompt. Never invent a number: anything the cost file cannot supply is `null` with
  `cost_available: false`.
- Append to this session's file if it exists; never edit or delete an existing line or
  file. Records are evidence.
- Test-fixture model names live only under `tests/fixtures/` and must never be written
  here.

## Semantics

- **Quarantine:** records whose `resolved_model` is null, `<synthetic>`, or absent from
  `hooks/model-rates.json` are excluded from pass-rate aggregation and reported on the
  scoreboard's `unattributed` line — surfaced, never folded into a real model's row.
- **Canonical main or it doesn't count.** Records flow to the canonical repo by
  ordinary git, exactly like `docs/gaps/` records, and count for routing-table
  recalibration only once merged to canonical main.
- **Evidence, not workflow.** Nothing reads these records automatically; changing the
  orchestrator's routing table is a human edit informed by the scoreboard.
