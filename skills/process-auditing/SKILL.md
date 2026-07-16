---
name: process-auditing
description: Assess whether a multi-phase effort still follows its approved intent, route, gates, and evidence. Use when running a checkpoint process audit, reviewing a charter amendment, investigating orchestration drift, or interpreting process-assurance outcomes; use reviewing instead for code or spec quality.
---

# Process Auditing

Job: judge the workflow against its approved reference and independent evidence. This is process assessment, not code review and not a second orchestrator.

Read `CONTEXT.md` if present so task and phase names match the project. Use the active process-assurance contract for marker and state details; the portable protocol is summarized in [protocol.md](references/protocol.md).

## Establish the reference

Use the active, human-approved charter version: objective, delivery target, scope, non-goals, acceptance criteria, route, and required checkpoints. A later amendment is a new version, never an edit to history.

Treat the orchestrator's ledger and summary as claims. Check them against the raw artifacts available to the audit: request, approved plan, repository state, dispatch receipts, verification results, approval records, and the current evidence manifest. Missing or inaccessible required evidence cannot produce `PASS`.

## Keep the role narrow

The auditor assesses and reports. It does not dispatch, edit, approve, waive, amend, deploy, or perform the protected transition. Use a fresh reviewer invocation carrying the charter and evidence package rather than the orchestrator's accumulated conversation.

At every configured checkpoint, evaluate these questions in order:

1. Does the active charter still represent approved intent?
2. Is the effort still pursuing the approved outcome and delivery target?
3. Does the route still match observed size and risk?
4. Were required profiles, gates, permissions, and independence preserved?
5. Are findings, repairs, and decisions correlated to this task and frontier?
6. Did later edits invalidate earlier evidence?
7. Is the requested transition permitted now?
8. Does closeout overstate completion or omit delivery work?
9. Do repeated repairs, reroutes, or amendments expose a process gap?

Each answer is `SATISFIED`, `VIOLATED`, or `NOT_APPLICABLE` and needs positive rationale plus
direct evidence references. Every violated rule has a finding and every finding points to a
violated rule. `NOT_APPLICABLE` explains why the rule cannot apply; it is not a substitute for
missing evidence.

## Select one consequential outcome

- `PASS` means every rule is satisfied or validly not applicable and there are no findings.
- `REMEDIATE` means the process can return to the active charter through a concrete correction.
- `HUMAN_DECISION` means the resolution changes approved intent, accepts risk outside it, abandons work, or exhausts the bounded correction path.

There is no advisory warning state. Mixed findings take the strongest required outcome. A control or transport failure is recorded as an audit failure, never converted into a verdict.

## Preserve finding and amendment history

Continue a finding under the same lineage when its rule and affected element are unchanged. Transport retries do not count as correction attempts. When the contract's remediation limit is exhausted, escalate; the orchestrator may correct but cannot waive.

Keep amendment proposal, independent amendment assessment, and human decision separate. Record the origin and whether work already occurred. Retroactive proposals can change the charter only prospectively; they never delete or relabel an earlier violation. Frequent amendments are an effectiveness signal.

An amendment proposal freezes available transition authorization while it is assessed. Return
`REMEDIATE` when its evidence or boundaries need correction. A retroactive proposal cannot receive
routine `PASS`; it either needs correction or explicit human decision, and a corrected package is
a new proposal with its own identity.

## Distinguish observation from control

In `SHADOW`, record every checkpoint outcome but do not mint authorization, block workflow, or represent the run as enforced. In `ENFORCE`, only the deterministic guard consumes a current exact `PASS` authorization. If that guard or its evidence binding is unavailable, disclose enforcement as unavailable rather than implying the reviewer has blocking power.

Clean audits may be silent to the task user but remain durable. Non-clean closeout outcomes must be disclosed.

## Judge whether the control works

Checkpoint results measure compliance for one run. Effectiveness requires longitudinal evidence: escaped violations, false blocks, human overrides, amendment origin/frequency, remediation convergence, added time and cost, unavailable-control intervals, and errors caught beyond existing verification/review.

This skill is unadmitted until `evals/process-auditing/record.md` contains the commissioned baseline and with-skill runs required by the authoring standard.
