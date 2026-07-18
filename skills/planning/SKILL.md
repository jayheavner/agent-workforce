---
name: planning
description: Write versioned implementation task contracts a builder can execute from current repository evidence — stable outcomes and invariants, bounded discretion, preflight, TDD, verification, and self-review.
---

# Planning

Job: turn an approved spec into a versioned execution contract a skilled engineer with zero
context can execute against the repository that actually exists. Save plans where the project
keeps them (default: `plans/YYYY-MM-DD-<feature>.md`).

## Before writing tasks

- **Spec completeness gate:** confirm the spec fixes product behavior, interfaces, invariants,
  risk boundaries, and acceptance evidence. Resolve consequential gaps through `interviewing`;
  never hide an invented decision in a task.
- **Investigate first:** inspect the current paths, symbols, tools, tests, policies, and workspace
  that the plan depends on. State verified repository facts as facts and label anything the
  builder must confirm as a builder-preflight hypothesis.
- **Scope:** if independent subsystems can deliver and verify value separately, plan them
  separately. Keep coupled acceptance behavior in one contract.
- **File responsibilities:** name confirmed files and their responsibilities. Mark an uncertain
  path `candidate`; do not invent stable line ranges.

## Plan header

Every new plan declares `execution-contract: 1` and opens with Goal, Architecture, Tech Stack,
and Global Constraints. Quote project-wide spec requirements one line each. Resolve
`policy:workspace-isolation` from project policy, state its source and exact value, and make the
selected workspace implicit in every task. Resolve `policy:dependency-freshness` before pinning
any dependency. Include one pre-implementation security pass: no secrets in code or logs, inputs
validated at boundaries, and errors sanitized before display.

## Tasks

A task is the smallest independently reviewable acceptance slice with its own test cycle. Assign
each task a stable identity unique within the plan.

Four of a task's subsections are load-bearing contract blocks: `Interfaces and invariants`,
`Acceptance mapping`, `Executable examples`, and `Escalation triggers`. Write each as an explicitly
delimited block a reader can extract unambiguously — a bounded block, not a prose paragraph folded
under a heading.

### Model-neutral by design

The plan carries no model reference. Per-model framing is applied by the orchestrator at dispatch
time, not authored into the plan. See `skills/agent-workforce/references/plan-formatting.md` for
the framing rationale.

### Task identity

Use `T<number>-<short-slug>`. Builder results, status notes, verifier findings, reviewer findings,
and repair dispatches use the plan path plus this identity.

### Outcome

State one observable result as behavior or state, not activity.

### Acceptance mapping

Name the exact spec requirements this task proves and the evidence that will prove each one.

### Files and responsibilities

List confirmed Create / Modify / Test paths and each file's responsibility. Mark likely paths
`candidate` for preflight. Use a line range only when it identifies a stable existing contract.

### Interfaces and invariants

Fix inputs, outputs, data shapes, public signatures, ordering, security boundaries, and decisions
the builder must not change. Do not pin internal helper structure without a stated contract reason.

### Executable examples

Give concrete Given/When/Then or input/output behavior, including at least one boundary or failure
case. Define observable behavior without pre-writing the production implementation.

### Preflight checks

List load-bearing repository observations required before editing: workspace and dirty tree, named
paths and symbols, tools and dependencies, policy compatibility, and whether the proposed red seam
can exercise the behavior.

### TDD and verification contract

State the red behavior, smallest green check, and broader acceptance verification. Give an exact
command only when repository evidence supports it; otherwise require the builder to discover and
report the equivalent capability.

### Executor discretion

Name the mechanical choices allowed without amendment. Default discretion may include an
equivalent existing test seam, corrected helper/path/line/mock detail, an installed or
standard-library mechanism, internal helper boundaries, and directly affected fixture updates.
It never includes scope, approved behavior, security posture, data semantics, or outward effects.

### Escalation triggers

Name concrete conditions that exceed discretion or change a fixed decision. Do not write a generic
"if the plan is wrong, stop."

### Commit intent

Name expected paths and one Conventional Commit subject. The builder stages only its own reviewed
diff after a green slice.

## Contract evolution

The planning skill produces v1. Approved legacy plans remain valid artifacts; their consuming
rules live with builder and orchestrator. Never silently amend an approved plan just to upgrade
its schema.

## Self-review

After writing the full plan, fix findings inline:

1. **Coverage:** every spec requirement maps to a task; list and close gaps.
2. **Placeholder scan:** remove TBD, TODO, guessed decisions, "implement later," generic error
   handling, unbounded test requests, and undefined cross-task names.
3. **Consistency:** later names and interfaces match their definitions.
4. **Architect intent:** every fixed decision and its rationale survives task decomposition.
5. **Builder feasibility:** paths, dependencies, tools, policies, and commands are evidenced or
   explicitly labeled for runtime preflight.
6. **Verifier observability:** every acceptance behavior has evidence the verifier can reproduce
   without trusting the builder's report.

DRY. YAGNI. TDD. Frequent commits.
