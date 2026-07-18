# Plan-formatting: dispatch framing reference

This file is the single source of truth for how a dispatched builder's envelope is framed. The
durable plan artifact itself carries no model reference (see `skills/planning/SKILL.md`,
"Model-neutral by design"); framing is applied by the orchestrator at dispatch time, and every
consumer (orchestrator, builder, generated Codex profiles) cites this file rather than restating
its rules.

## The two-axis model

Framing is **notation(vendor) × stance(tier)** — two composed axes, not one enum. A dispatch's
framing is the product of both: a Claude reasoning-tier upshift is `claude-xml` + `outcome-first`
together, not a fifth standalone label.

- **notation(vendor)** — which markup family the target model reads most naturally.
- **stance(tier)** — whether the dispatch leads with outcome or with prescriptive step order.

These compose independently. Any vendor can pair with either stance; the tier axis does not imply
a vendor and the vendor axis does not imply a tier.

## Fixed labels

Exactly these four labels exist. No consumer may introduce a fifth or rename one:

- `claude-xml` — notation for the Claude family.
- `gpt-markdown` — notation for the GPT family.
- `outcome-first` — stance for a reasoning-tier upshift.
- `unframed-fallback` — the safe default on an unrecognized or ambiguous vendor family.

## Family → notation table

| Family | Notation | Shape |
|---|---|---|
| Claude (Sonnet, Opus, Fable, Haiku) | `claude-xml` | XML tags: `<task>`, `<plan_reference>`, `<in_scope_slice>`, `<terminal_result>` |
| GPT (Terra, Sol, Luna — see `model-policy.md`) | `gpt-markdown` | Markdown headers of the SAME fields: `## Task`, `## Plan reference`, `## In-scope slice`, `## Terminal result` |

Both notations carry the identical four fields. Only the markup differs — XML tags for Claude,
Markdown headers for GPT. Neither notation contains any of the plan's own contract prose; both
only reference the plan's named blocks by name (see "Reference, never restate" below).

## Tier → stance rule

A **reasoning-tier upshift** (dispatching a model above its default tier for this role — e.g. an
Opus or Sol architect stepping up to a harder synthesis) uses the `outcome-first` stance: lead with
the outcome and the fixed invariants, and de-emphasize prescriptive step ordering. A default-tier
dispatch uses the plan's ordinary step-by-step framing as-is; `outcome-first` is additive only on
an upshift, never the default.

## Reference, never restate

The envelope references the plan's named blocks — `Interfaces and invariants`, `Acceptance
mapping`, `Executable examples`, `Escalation triggers` (fixed in `skills/planning/SKILL.md`) — by
name only. It never copies their content into the envelope. This keeps the envelope unable to
contradict the plan: there is exactly one place the contract text lives, and the envelope only
points at it.

## Safe fallback

If the target model's vendor family is unrecognized or ambiguous, the orchestrator dispatches
un-framed: apply `unframed-fallback` and log an observable noting the unrecognized family. An
un-framed dispatch is still a valid, complete dispatch — the plan file itself carries the full
contract regardless of framing. Never guess a notation for an unrecognized family.

## Worked examples

### (a) Correct Claude XML envelope

```
Given: the target model is Sonnet (Claude family), default tier.
When: the orchestrator dispatches the builder for task T3.
Then: the envelope is:

<task id="T3-orchestrator-framing">
<plan_reference>docs/plans/2026-07-18-model-tailored-plan-formatting.md#T3-orchestrator-framing</plan_reference>
<in_scope_slice>Interfaces and invariants; Acceptance mapping; Executable examples; Escalation triggers — read from the plan reference above.</in_scope_slice>
<terminal_result>Report RESULT_STATUS and the commit made, per the plan's Commit intent block.</terminal_result>
</task>
```

No plan prose is copied in — only the path and block names are cited.

### (b) Correct GPT Markdown envelope

```
Given: the target model is Sol (GPT family), reasoning-tier upshift.
When: the orchestrator dispatches the architect for a novel multi-system design task.
Then: the envelope is:

## Task
T3-orchestrator-framing

## Plan reference
docs/plans/2026-07-18-model-tailored-plan-formatting.md#T3-orchestrator-framing

## In-scope slice
Interfaces and invariants; Acceptance mapping; Executable examples; Escalation triggers — read
from the plan reference above.

## Outcome first
Lead with the task's Outcome block and its fixed invariants before working through ordered steps.

## Terminal result
Report RESULT_STATUS and the commit made, per the plan's Commit intent block.
```

This composes `gpt-markdown` + `outcome-first` — same four fields as (a), Markdown headers instead
of XML tags, plus the outcome-first stance section because this is a tier upshift.

### (c) Malformed envelope — MUST be rejected

```
Given: the target model is Sonnet (Claude family).
When: the orchestrator drafts a dispatch that pastes the task's full "Interfaces and invariants"
  and "Executable examples" prose directly into the envelope instead of citing them by name.
Then: this envelope is malformed and MUST be rejected. Restating plan content inside the envelope
  creates a second copy of the contract that can drift from the plan file — exactly what the
  reference-never-restate rule in this file forbids. The correct envelope cites the block names and
  the plan path only, as in example (a).
```

## Non-goals

This file does not claim framing changes measured output quality. That question is gated behind a
production baseline (see the plan's Stage 2, T7/T8) and is out of scope here. This file only fixes
the mechanics of notation and stance so dispatch is deterministic and citable.
