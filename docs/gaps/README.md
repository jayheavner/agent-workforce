# Gap records

> **Note (2026-07-18):** as of the autonomy-first redesign, the primary path for a
> capability gap met mid-task is the `growing-the-team` skill: **create** the missing
> skill or agent as a draft in the workforce repo (marked `provenance: provisional`),
> **use** it immediately for the task at hand, and **disclose** it at closeout for
> human review and possible upstreaming. This directory remains for gap records a
> session could not act on. The record schema below is unchanged.

One file per detected capability gap, written by the scribe on the orchestrator's
dispatch. Filename: `GAP-<YYYYMMDD>-<kind>-<slug>.md`. The orchestrator assigns
`<kind>-<slug>` in the dispatch — slug at field granularity (`payroll`, never
`payroll-withholding`); coarse slugs over-link, which is the safe direction for the
promotion trigger. Same `<kind>-<slug>` = same gap.

Spec: `docs/superpowers/specs/2026-07-12-gap-detection-capability-loop-design.md`.

## Schema (v1)

```
# GAP-<YYYYMMDD>-<kind>-<slug>
- schema: 1
- kind: domain | fit | permission/tool | process
- detected: <date> / <project> / <detector: architect domain check | orchestrator gate review>
- task: one line on what was being attempted
- gap: what was missing
- fallback: what the team did instead (e.g. "uncertified researcher backfill, sources cited in spec")
- recurrence: filenames of earlier records with the same <kind>-<slug>, if any
- status: open | promoted → <spec/ticket path> | declined — <reason>
```

## Rules for the scribe

- List this directory before writing; link every earlier record with the same
  `<kind>-<slug>` on the `recurrence:` line.
- Never edit or delete an existing record. Records are evidence.

## Semantics

- **Evidence, not workflow.** A record freezes once its status leaves `open`:
  `promoted` points at the spec or ticket where the work is tracked; `declined` keeps
  the reason. This directory never becomes a second ticket system.
- **Declined is not terminal — the reason carries forward.** A new detection with a
  previously-declined identity is still logged, links the declined record in
  `recurrence:`, and is presented at the gate with the decline attached
  (`— note: declined <date>, reason: <reason>`). It re-opens the question only when
  the human says the stated reason no longer holds.
- **Canonical main or it doesn't count.** Promotion decisions happen only against this
  repository's main. A record not in canonical main does not exist for promotion purposes;
  local and degraded-path records count for nothing until merged. Default
  promotion trigger: a second record with the same `<kind>-<slug>`, or the human
  explicitly asking — promotion is always the human's decision.
- **Relation to `PARKING-LOT.md`:** the parking lot holds human-curated deferred
  *ideas*; this directory holds machine-written observed *evidence*. An idea may cite
  gap records as its promotion trigger.
