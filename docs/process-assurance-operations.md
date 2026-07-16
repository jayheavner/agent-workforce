# Process assurance operations

## Supported control

The implementation uses the existing reviewer as a fresh process-audit sidechain. It persists a
versioned charter and append-only canonical event chain outside the project, verifies the snapshot
and event hashes on every read, and serializes mutations with a session lock. Raw prompts,
artifact bodies, command output, and secrets are not stored.

The closed verdicts are `PASS`, `REMEDIATE`, and `HUMAN_DECISION`. Every assessment carries all
nine ordered checklist evaluations (`SATISFIED`, `VIOLATED`, or `NOT_APPLICABLE`) with positive
rationale and direct evidence references. Violated rules and findings must correspond exactly.
`PASS` in `ENFORCE` creates one authorization bound to the charter, checkpoint, transition, and
evidence-manifest digest; the builder hook consumes it once before dispatch. `SHADOW` never creates
or consumes authorization.

## Feature modes

- `OFF` is the installation default and performs no process-assurance work.
- `SHADOW` records checkpoints, audit failures, amendments, and effectiveness evidence without
  blocking workflow.
- `ENFORCE` fails closed when the Standard/Large pre-builder charter, request, result, transition,
  state, or authorization is missing, malformed, stale, mismatched, corrupt, or reused.

Promotion is operational, not inferred from documentation. Do not enable `ENFORCE` until the
installed adapter's sidechain result capture and builder PreToolUse guard have passed a live
shakedown. The implementation does not claim exactly-once external effects or builder-internal
effect fencing; those guarantees remain out of scope for the protected pre-dispatch transition.
Feature mode is immutable within one assurance session; promotion starts a new session and retains
the prior SHADOW directory as rollout evidence.

## Marker lines

Each marker occupies one line followed by one compact JSON object:

- `WORKFORCE_CHARTER:` — initial approved charter.
- `WORKFORCE_PROCESS_AUDIT_REQUEST:` — checkpoint, requested transition, and evidence references;
  the state owner derives the Git manifest and active charter binding.
- `WORKFORCE_PROCESS_AUDIT_RESULT:` — the injected request hash, ordered evaluations, findings,
  verdict, and auditor identity.
- `WORKFORCE_TRANSITION:` — exact checkpoint and transition; the guard independently derives and
  compares the current evidence digest before consumption.
- `WORKFORCE_PROCESS_ASSURANCE_CLOSEOUT:` — honest disclosure of non-clean pre-closeout status.

Duplicate, malformed, wrong-port, stale, or conflicting markers do not authorize a transition.
When Claude routes one tool call through both plugin-level and agent-level hooks, identical charter
and request initialization is idempotent. A consumed transition receipt is accepted only for the
same platform `tool_use_id`; a later dispatch cannot replay it.

## Amendments and remediation

Amendments use separate proposal, reviewer assessment, and human decision commands. The proposal
records origin and whether work already occurred and immediately invalidates available
authorization. The reviewer can return `REMEDIATE`; that proposal cannot reach human decision and
a corrected package is submitted as a new proposal. A retroactive proposal cannot receive routine
`PASS`; it requires remediation or `HUMAN_DECISION`, must be prospective if approved, and preserves
earlier charter/assessment history.

Initial findings create stable lineages. Only accepted remediation submissions increment the
lineage count. After two unsuccessful remediation submissions, a continuing finding must escalate
to `HUMAN_DECISION`; rewording the same rule and affected element cannot reset the lineage.

## Operator CLI

All commands require `--state-root`, `--session`, and `--mode`. Mutating commands read a JSON
object from a named file or `-` for standard input.

```bash
bin/agent-workforce-process-assurance --state-root STATE --session TASK --mode SHADOW status
bin/agent-workforce-process-assurance --state-root STATE --session TASK --mode SHADOW verify
bin/agent-workforce-process-assurance --state-root STATE --session TASK --mode SHADOW metrics
bin/agent-workforce-process-assurance --state-root STATE --session TASK --mode SHADOW amendment-propose proposal.json
bin/agent-workforce-process-assurance --state-root STATE --session TASK --mode SHADOW amendment-assess assessment.json
bin/agent-workforce-process-assurance --state-root STATE --session TASK --mode SHADOW amendment-decide decision.json
bin/agent-workforce-process-assurance --state-root STATE --session TASK --mode SHADOW effectiveness-record outcome.json
```

Effectiveness outcomes require independent evidence references and an adjudicator identity. The
scorecard retains false blocks, human overrides, escaped violations, amendment-proposal frequency,
remediation frequency, missing checkpoints, audit failures, and the underlying outcome records.

## Recovery

Each mutation journals its resulting snapshot before appending the event. If interruption occurs
before the event is durable, recovery discards the uncommitted journal; if the event is durable,
recovery completes the exact matching snapshot. On restart, `verify` also checks the snapshot
digest, contiguous event filenames, sequence, previous-event links, per-event digests, head digest,
and storage capacity. Any mismatch is `STATE_CORRUPT` and blocks enforcement; do not delete or
hand-edit state to make a transition pass. Preserve the directory for incident review and start a
separately authorized recovery or a new task session.
