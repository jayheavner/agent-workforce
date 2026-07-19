# Autonomy-First Redesign

**Date:** 2026-07-18
**Status:** Approved by owner directive ("MAKE THIS BETTER" — full latitude, no questions), implemented in this change set.
**Supersedes:** the process-assurance charter machinery, the execution-contract envelope, the tiered critic pipeline, and the 475-line orchestrator contract. Git history preserves all of it.

## The owner's requirement, verbatim in spirit

Hand the team a task; it works the problem to completion with no involvement. Fast, cost-effective, closes out properly every time — including an exact cost report that never has to be asked for. Bespoke agents with set models, effort, and permission boundaries; skills that guide common and novel work; and a team that grows itself new skills and agents when it meets a problem it doesn't have tooling for.

## Diagnosis — why the previous system failed

Evidence: the 2026-07-09 csv2json transcript, the 2026-07-14 Slack-links postmortem, the 2026-07-17 $51-session plan, and live inspection of both installed profiles on this machine.

1. **Fixes never reached production.** Every incident produced repo fixes; the install step was manual, terminal, and auth-blocked, so no fix ever ran. On 2026-07-18 both profiles held a July-13 build: 75 drift lines, the closeout Stop hook file absent, two agents never installed, three retired hooks still present. The owner has been experiencing bugs that were "fixed" days earlier. **A fix that requires a human to deploy it is not a fix.**
2. **Process weight was constant, not proportional.** A trivial CSV→JSON script consumed 11 dispatches, 2 approval gates, 4 scribe status notes, ~45 minutes, and ~$3 plus orchestrator usage. The tier system modulated artifact length, not structure — every phase was a dispatch, every fact crossed a dispatch boundary (the orchestrator had no shell), every status update was a paid scribe run.
3. **Behavior was specified in prose and the prose grew with every failure.** The orchestrator contract reached ~9,300 words / 475 lines. Sessions violated rules while quoting them ("I named haiku in my triage but didn't set the override"). Only mechanisms (hooks) ever changed behavior; each incident added one hook and pages of prose. The contract's size *was* the failure: attention exhausted on process is attention taken from the task, and closeout — living at the end of the longest document — was the first thing dropped.
4. **Closeout failed at both ends.** Unenforced live (hook absent); mis-specified at HEAD (cost report gated on reaching a "final gate" that decayed sessions never reach; the orchestrator's own usage — plausibly the largest cost line — permanently excluded from every "exact" report; a blended-estimate fallback still installed). When enforcement did run, it fired while dispatches were in flight and demanded facts it couldn't know, producing 67 rote receipts and compliance theater instead of closure.
5. **Questions were the wrong questions.** The system asked (a) preference questions it had already answered ("recommend approve as-is"), (b) fact questions a dispatch could resolve, (c) approval questions its own standing-authorization rule covered. Each cost an unbounded human round-trip.
6. **The self-improvement loops never produced data.** Zero gap records, zero valid telemetry records — both depended on the model remembering multi-step choreography at the moment of maximum context exhaustion, and nothing blocked on their absence.

## Design principles

1. **Enforce by mechanism, guide by judgment.** Anything that must happen every time (cost report, freshness, secrets, audit trail) is a hook or script that cannot be forgotten. Anything that needs judgment (routing, scoping, questions) is short prose the model can actually hold. No new prose rule may be added where a mechanism can do the job; no mechanism may demand what it cannot verify.
7. **The launcher is the deployment.** `bin/agent-workforce` verifies freshness and self-installs before the session starts. A stale or half-installed profile becomes impossible to run quietly.
2. **Process weight is proportional to the task, with a floor of one.** The default route for clear, contained work is ONE specialist doing plan+build+test, then one verification pass. Specialists multiply only when the task genuinely needs isolation, parallelism, independent review, or privileged credentials.
3. **Facts are free.** The orchestrator holds read-only shell access for observation (git state, file checks, transcripts). A fact-check is a command, not a dispatch, and never a question to the human.
4. **The four gate conditions are the entire question policy.** Ask only for: a genuine values/risk fork with materially different outcomes; a material scope expansion; an unauthorized outward/destructive mutation; an irreducible human action (credentials, hardware). Convention-level choices are decided and disclosed at closeout. Fact-shaped questions are lookups. A declined question is settled.
5. **The cost report is computed, not remembered.** A deterministic script prices the full session — orchestrator's own usage included — from transcripts at list rates. The Stop hook computes it and hands it to the model; the model's only job is to include it. There is no estimate path and no way to forget.
6. **The team grows itself.** A capability gap met mid-task produces a draft skill (or agent) in this repo, marked provisional, used immediately, disclosed at closeout for review and upstreaming to `jayheavner/skills`. Record-and-wait is replaced by create-use-disclose.

## What is removed

- **Process assurance** (charters, audit markers, SHADOW/ENFORCE, nine-rule reviewer audits, its hooks, CLI, tests, and skill). It never left OFF, its qualification never ran, and its prose consumed more contract than any other feature.
- **The execution-contract envelope** (RESULT_ID / SUPERSEDES_RESULT / typed-stop taxonomy / correlation frontier). Builders report outcomes, evidence, deviations, and blockers in plain structure; the orchestrator routes on substance.
- **The mandatory spec-critic pipeline and decision-inventory audit.** The reviewer still critiques plans for standard+ work; the two-questions discipline survives as three sentences, not three sections.
- **Scribe ceremony.** Status notes at closeout and at genuine interruption/handoff only. Telemetry is written by machine, not by a paid dispatch.
- **The blended-estimate cost path**, everywhere, permanently.
- **~340 lines of orchestrator contract.** The new contract fits in ~130 lines including the roster table.

## What is kept

- Model/effort/permission pins per agent, with per-dispatch downshift/upshift (unchanged philosophy: no role defaults to Fable; upshifts are named).
- The secrets hook (the one blocking rule), the audit log, the dispatch-type guard, the serialization guard, and the budget ratchet (the $51 stop-loss).
- Reviewer independence (different model than builder) for standard+ code.
- Max-two repair loops, then escalate with history.
- The vendored skills framework, re-synced with upstream `reviewing` (receiving-review chair).
- The Codex surface, regenerated from the new contracts via `scripts/render_codex_agents.py`.

## Mechanisms (the load-bearing changes)

1. **`bin/agent-workforce-cost-report`** — reads the main-session transcript and every subagent transcript, prices all of it from `hooks/model-rates.json` (updated to current list rates, Fable 5 included), and prints one exact table: per model × (input, output, cache-write, cache-read, cost), per-dispatch attribution, grand total including the orchestrator's own session. Unknown model IDs are listed as exact unpriced token counts, never multiplied by a guess.
2. **Closeout Stop hook (rewritten)** — skips while dispatches are in flight; on the final stop of a task session, if the last message carries no cost table, blocks once and supplies the computed table in the reason so compliance is a paste, not a memory feat. Also requires an honest completion line when the tree is dirty. Nothing else.
3. **Self-installing launcher** — `bin/agent-workforce` runs the freshness check against the active profile and installs on drift before starting the session, for any `CLAUDE_CONFIG_DIR`.
4. **Machine telemetry** — the cost hook already records per-dispatch facts; the closeout script emits the telemetry rows itself. No scribe involvement, no "canonical main" gate.
5. **`growing-the-team` skill + provisional agents/skills convention** — the concrete procedure for the self-growth loop, carried by the architect (skills/agents authoring) under the vendored `writing-skills` discipline.

## Route table (the whole thing)

| Shape | Route |
|---|---|
| Question / lookup | Answer from evidence (own shell for local facts, researcher for the world). Never from memory. |
| Trivial action | ONE dispatch (executor or builder), cheapest capable model. |
| Clear, contained build | builder (plans+builds+tests, TDD) → verifier. Reviewer added only for risky surfaces. |
| Real design decisions | architect (one combined spec+plan) → builder → verifier ∥ reviewer. |
| Multi-system / high-risk / production | researcher (if open questions) → architect (deep) → builder(s) → verifier ∥ reviewer → deployer (when authorized) → smoke. |
| Symptom ("X is broken") | debugger first; route the fix by its root cause. |
| Research / ops / documents / tickets | specialist → artifact → outward action if authorized. |

Every route ends at the same place: verified outcome, committed delta (unless told otherwise), one status note, and the computed cost table.
