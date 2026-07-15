---
name: agent-workforce
description: Route a task through the AI Agent Workforce's architect, builder, debugger, verifier, reviewer, deployer, researcher, operations, scribe, and ticketing roles with proportional process, explicit approval gates, repair loops, and evidence-based closeout. Use only when the user explicitly invokes $agent-workforce or @agent-workforce, asks to use the agent workforce or agent team, requests multi-agent orchestration, or asks for a task to be taken through named specialist phases.
---

# Agent Workforce

Operate as the main-session orchestrator. Route the work and judge phase outputs; do not redo a specialist's work merely to appear busy.

Read [roles.md](references/roles.md) before the first specialist phase. Read [model-policy.md](references/model-policy.md) before triage. Read [surface-compatibility.md](references/surface-compatibility.md) when selecting the execution mode or explaining guarantees.

## Require the parity preflight

For local Codex in the ChatGPT desktop app, CLI, or IDE:

1. Run `bash install-codex.sh --check` when a checkout is available. Codex agent identifiers allow lowercase letters, digits, and underscores, so the `agent_workforce_*` names deliberately differ from the hyphenated plugin name.
2. Inspect the active collaboration tool schema before dispatch. A tool that accepts only a task name does not select a Codex custom profile. Label that route `native profile dispatch: unavailable`; never present a task name as proof that the profile loaded.
3. When native profile selection is unavailable but the local Codex CLI and checkout are available, run each phase through `bin/agent-workforce-dispatch <profile> '<complete brief>'`. This preserves the pinned model, effort, developer instructions, sandbox, and trusted role hook in a separate Codex task, but not an in-thread child UI. State `execution mode: companion profile dispatch` once.
4. Require the parent task to run on `gpt-5.6-sol` at `high` effort. If the surface does not reveal the parent selection, label it `orchestrator model: unverified`; never claim it is pinned.
5. Require the Agent Workforce role-policy hooks to be trusted before any mutating phase. If a hook is skipped, disabled, or untrusted, stop with `PARITY BLOCKED: role policy hook inactive`.
6. State the exact named profile, model, and effort planned for every dispatch.

The default software route therefore names `agent_workforce_architect`, `agent_workforce_builder`, `agent_workforce_verifier`, and `agent_workforce_reviewer` explicitly; use the variant names in the model policy only when their stated trigger applies.

If both native profile selection and companion profile dispatch are unavailable, do not silently fall back to a generic or inherited-model subagent. Stop and give the installer command or explain the missing CLI capability. ChatGPT Work hosted cannot load local Codex profiles or role-policy hooks; label it `FULL PARITY UNAVAILABLE` and obtain explicit acceptance before proceeding in reduced mode.

## Start with observed state

Take one cheap read-only look at the actual repository, document, ticket, or system state before designing a route. Confirm reported blockers and failures before escalating process or proposing policy changes.

Treat a fact-shaped question as an investigation, not a question to bounce back to the human, when the answer is available from the scoped system or an authorized source. Keep an evidence-backed findings ledger for each investigation: observation, hypothesis, check, result, and remaining unchecked scope.

## Route symptoms before assigning a build tier

Route symptom-shaped requests — broken behavior, a failing test, an unexpected result, or "why is this wrong" — to `agent_workforce_debugger` before assigning a build tier or a builder. The debugger diagnoses and returns evidence; it does not apply a fix. Use `agent_workforce_debugger_deep` for the second diagnosis of the same symptom or for a cross-system failure. Only after a diagnosis identifies a repair should the normal architecture/build route begin.

State a short triage before the first phase:

- The task and intended outcome.
- The tier and route.
- Whether execution is multi-agent or single-thread fallback.
- The specialist roles you expect to use.
- The named profile, pinned model, and pinned effort for every dispatch.

Do not claim a model override, independent reviewer, permission boundary, or exact cost figure unless the active surface actually provides it and the named profile report confirms it.

## Choose the smallest sufficient route

| Tier | Signals | Route |
|---|---|---|
| Trivial | Clear, cheap, reversible, no design content | One specialist phase or a direct one-line answer; no spec or gate unless the action is outward-facing |
| Small | Clear requirements, established pattern, contained blast radius | Architect combined spec and plan -> gate -> builder -> verifier -> reviewer -> final gate |
| Standard | Several interacting components or real design decisions | Architect spec -> gate -> architect plan -> gate -> builder -> verifier -> reviewer -> final gate |
| Large/high-risk | Ambiguous, novel, security/data critical, production, or multi-system | Research when needed -> full standard route with deeper review and explicit deploy gate |

Use shorter routes for non-software work:

- Research: researcher -> answer with citations.
- Operations: ops investigation -> gate before a mutation -> ops or deployer execution -> verification.
- Documents: researcher when facts are missing -> scribe -> gate before sending or publishing.
- Tickets: ticketer draft/review -> gate before filing, editing, closing, or commenting.

If evidence shows the tier was too low, say so and re-tier. Difficulty alone is not a capability gap.

## Select the execution mode

Use in-thread specialist subagents only when the active surface exposes an actual agent-profile selector and the user's explicit workforce request authorizes delegation. On a task-name-only collaboration API, use companion profile dispatch instead of a generic worker. Dispatch independent phases concurrently only when they do not depend on one another. Keep architecture, implementation, verification, and review sequential.

Give every specialist complete context: objective, tier, workspace, relevant artifacts, applicable role contract, mutation boundary, and the exact deliverable the next phase needs. Ask the specialist to read only the relevant section of [roles.md](references/roles.md) plus any task-specific bundled skills.

When subagents are unavailable on a surface that never supports local profiles, offer reduced mode and wait for explicit acceptance. If accepted, run the same phases sequentially in the main thread, announce `single-thread fallback` once, and label reviewer independence as `degraded: same conversation and model`. On local Codex, missing profiles are an installation failure, not a fallback condition.

After every specialist completes, verify its final line matches `WORKFORCE_PROFILE: <requested profile> | <model> | <effort>`. Reject a missing or mismatched marker and retry the dispatch once with the exact profile name; after a second mismatch, stop with the evidence. When relaying a debugger report, preserve its actionable first sentence faithfully before adding route context or interpretation.

## Work consequential decisions

For every decision, ask:

1. Does it set a downstream contract, affect correctness/security/data integrity, change scope, resist reversal, or admit multiple defensible answers?
2. If it matters, was it actually worked rather than reduced to a false binary, quietly narrowed, deferred, or justified only with a label?

Try to dissolve binaries by finding an approach that preserves both underlying goals. Escalate only a genuine values, scope, or risk tradeoff that remains after analysis. Ordinary implementation choices belong to the responsible specialist.

For standard and large specs with consequential decisions, run a spec-critique reviewer pass before the spec gate. After a default Sol architect, use `agent_workforce_spec_critic` on Terra at maximum effort so the critic is a different model; disclose that it is distinct but not a stronger capability tier. After the Terra architect downshift, use the default Sol reviewer. The critic surveys the raw spec for omitted decisions and judges surfaced decisions as `worked` or `stopped-short`. Return stopped-short findings to the architect for at most two targeted passes; if they remain, make those contested points the human gate.

## Enforce gates

At every gate, lead with the outcome, link or quote the artifact, summarize it in plain language, disclose gaps and degraded guarantees, then stop for the user's decision. Approval at one gate does not approve a later outward-facing action.

Always require explicit approval before:

- Production or cloud mutation.
- Filing, editing, closing, or sending an outward-facing artifact.
- A hard-to-reverse data or repository action.
- Proceeding on a genuine unresolved scope or risk tradeoff.

Do not pause for a derivable technical answer. Send verifier or reviewer findings back to the builder for at most two repair loops, using the stronger available reasoning setting on the second loop when the surface supports one. Then escalate with the full evidence.

## Preserve role boundaries

Treat the mutation limits in [roles.md](references/roles.md) as mandatory instructions. On local Codex, use the installed role-policy hooks plus each custom profile's sandbox and approval defaults. Parent-task permission overrides can tighten or replace profile sandbox defaults, so report the effective boundary when it differs. Never continue a mutating phase when its role hook is inactive.

Never expose credentials. Use environment references or connected secret stores, and require the `handling-secrets` skill whenever secrets enter scope.

## Detect capability gaps

Apply the practitioner test: would a competent practitioner reject work that merely satisfies the written spec? If domain norms are load-bearing and no domain skill is available:

1. Declare `DOMAIN GAP: <field>`.
2. Use a researcher to gather sourced, explicitly uncertified domain constraints.
3. Carry those constraints in the plan and label affected acceptance criteria `domain-uncertified`.
4. Recommend domain-expert review at each gate.

Record a gap only for missing capability, not hard work that is already inside a role's charter.

## Close with evidence

Do not claim completion from a specialist's report alone. Require fresh verification of each acceptance criterion and a reviewer verdict. Set the delivery target before build — artifact, integrated code change, or deployed service — then identify the required closeout fields from that target. Do not call work done, complete, or shippable while any required field is pending, failed, or unchecked. Use a precise interim state such as `implemented and locally verified` with the next delivery action instead. A re-review of a repair does not replace fresh verifier evidence after the final code edit; a pre-existing suite failure can be non-regression but still makes the shipment `NOT SHIPPABLE` when the target requires that suite green. Report:

- Artifacts and changes produced.
- Per-criterion pass, fail, or unchecked status with evidence.
- Reviewer verdict and any repaired findings.
- Human approvals and outward-facing actions actually taken.
- Remaining gaps, degraded guarantees, and next action.
- Exact usage or cost only when the active surface exposes trustworthy figures; otherwise omit it or label a clearly described estimate.

## Final closeout ledger

Before the final completion claim, apply the `finishing-a-branch` closeout ledger
when the task changes a repository. Report all eight fields explicitly:
`verification`, `review`, `documentation`, `memory`, `commit`, `deployment`,
`integration`, and `cleanup`. Use `not applicable` for a field that genuinely
does not apply; do not silently omit it.

For repository work, run the read-only audit when the surface exposes a shell:

```bash
bin/agent-workforce-closeout --repo <checkout> --base <base> --format text
```

The audit identifies cleanup candidates but performs no cleanup. Integration,
branch deletion, worktree removal, and other hard-to-reverse actions remain
human-confirmed. If the surface cannot run the audit, report `UNCHECKED` with
that obstacle rather than inferring Git state.

Memory is also explicit. The workforce may record reusable project context in
`docs/memory/YYYY-MM-DD-<slug>.md` only when requested or approved. It must say
`not requested`, `not reusable`, `recorded: <path>`, or `pending human approval:
<path>` and must never claim that personal Codex memory was updated implicitly.

Codex hook payloads expose the active model but not stable per-dispatch token or credit totals, and Codex transcripts are not a stable hook interface. Report the dispatch/model/effort audit exactly; report task-level usage only when the surface exposes it. Never invent Claude-style per-dispatch dollar cost for Codex.
