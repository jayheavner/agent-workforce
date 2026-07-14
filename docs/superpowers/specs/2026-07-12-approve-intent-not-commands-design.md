# Approve Intent, Not Commands — Trust-Model Redesign

**Date:** 2026-07-12
**Status:** Approved (human gate passed in-session; spec-panel critique incorporated)

## Problem

The team constantly hands the human bash commands to run, or blocks its own agents from
running them. Two root causes, verified in the live files:

1. The policy hooks (`hooks/agent-team-policy.sh` + lib + mutations, ~700 lines of regex)
   block not just dangerous commands but shell *syntax*: any `$(...)` or backtick, any `>`
   redirect, `mkdir/touch/cp/mv/rm`, `tar/zip`, `tee`, package installs, and interpreter
   one-liners — for builder, verifier, reviewer, ops, and deployer alike. Innocuous commands
   (`pytest > results.txt`, `echo $(date)`) are blocked, and the blocked agent escalates.
2. The instructions institutionalize the escalation: ops is told to "put the exact command
   in your report so the human can approve it at a gate"; the orchestrator's trivial tier
   says "if the action is faster from the human's own shell, say so and stop."

The human's requirement, verbatim in intent: approvals are of **ideas/process, not
commands** — and once approved, agents run **any** command the work needs, unprompted.

## Decisions (human-answered)

1. **Trust model:** tear out the blocklists entirely — no per-command policy enforcement.
2. **Hard floor:** "no hooks at all" as the starting answer; amended after panel critique
   (human re-decided): keep a **log-only audit hook** and keep the **secret-write guard
   enforced** as the single blocking rule. Everything else is instruction-level.
3. **Harness prompts:** `permissionMode: bypassPermissions` in team-agent frontmatter.
   Verified against current Claude Code docs: honored for subagents when the parent session
   runs in default mode; no settings.json opt-in needed; per-agent frontmatter hooks fire
   only for that agent's calls.
4. **Executor:** add a new general-purpose `executor` specialist for arbitrary shell work.

## The trust model

- **Approval lives at gates, and only at gates.** A gate presents *intent*: the goal plus a
  mutation scope in plain language ("ops will modify Okta group assignments as needed to fix
  X"), never command text and never an enumerated command list.
- **After approval, execution is silent.** No per-command prompts (bypassPermissions), no
  policy blocks (hooks removed), no commands surfaced to the human, ever.
- **The scope rule** (binding on executor, ops, deployer, builder):
  - An action **within the stated scope** runs without asking anyone.
  - An action **outside the stated scope but clearly required by the approved goal's own
    rationale** proceeds, flagged prominently in the agent's report.
  - An action **outside the approved goal** returns to the orchestrator. If it is a genuine
    scope change, that is a new gate — but a gate about the *change of intent*, still never
    about command text.
- **Worked examples:**
  1. Plan approved for a CLI tool; builder needs `npm install commander`. In scope → runs
     silently. (Previously: blocked, escalated.)
  2. Gate approved "fix the login outage — ops may modify the Okta app and its group
     assignments." Mid-task ops finds a stale IAM policy also breaking auth. Deleting it is
     outside the stated scope but inside the approved goal's rationale (restore login) →
     ops proceeds and flags it in the report with a reversal note.
  3. Same gate; ops notices an unrelated cost-saving opportunity (delete idle EC2
     instances). Outside the goal → report it; the orchestrator may open a new gate.
- **Reversal notes:** ops and the executor state the reversal path (or the word
  "irreversible") for each mutating action in their *reports* — never as a pre-approval.
  The deployer's record-known-good/rollback discipline is unchanged.

## Components

### Deleted

- `hooks/agent-team-policy.sh`, `hooks/agent-team-policy-lib.sh`,
  `hooks/agent-team-policy-mutations.sh`, `tests/test_policy_hooks.sh`.
- Every `agent-team-policy.sh` hook registration in agent frontmatter.
- The docwriter path restriction (architect/scribe writes) — instruction-level now.
- ops's "present the exact command to the human" rule; the orchestrator's "faster from the
  human's own shell" clause.

### Kept (not command-gating)

- `agent-team-dispatch-guard.sh` (prevents the silent-stall bug on missing
  `subagent_type`) — updated to include `executor`, ten specialists.
- `agent-team-cost.sh` + `model-rates.json` (closeout cost report), unchanged.

### New hook: `hooks/agent-team-audit.sh` (log-only)

PostToolUse on Bash for every command-running agent. Appends
`<UTC timestamp> role=<role> ran=<command>` to `~/.claude/logs/agent-team-audit.log`
(`AGENT_TEAM_AUDIT_LOG` overrides). **Always exits 0** — it can never block, prompt, or
fail an agent's tool call; a logging failure is silently swallowed by design. This is the
flight recorder: "what did the executor run at 2am" stays answerable.

### New hook: `hooks/agent-team-secrets.sh` (the single blocking rule)

PreToolUse on Bash and Write/Edit/NotebookEdit for every agent that can write. Ports the
two secret checks verbatim from the old policy lib (same `SECRET_RE`, same
`/dev/null`/fd-dup stripping): block a credential-bearing variable directed at a file via
redirect/tee, and block file content containing a credential-variable reference. Blocks are
logged to the same audit log. Nothing else blocks. This guard's false-positive surface is
effectively zero, so it cannot recreate command theater.

### New agent: `agents/executor.md`

General-purpose shell runner: Bash, Read, Glob, Grep, Write, Edit; `claude-sonnet-5`
(downshift `haiku` for single obvious commands, upshift `opus` for unfamiliar multi-step
system work); `permissionMode: bypassPermissions`; audit + secrets hooks.

**Approval check (deployer-pattern, load-bearing):** if the dispatch does not state that a
human approved the intent at a gate — or, for trivial-tier work, that the human directly
asked for the action — the executor runs nothing and reports exactly that. This closes the
only zero-approval execution path.

### Existing agents

- builder, verifier, reviewer, ops, deployer, architect, scribe: policy-hook registrations
  replaced with secrets (PreToolUse) + audit (PostToolUse on Bash, where Bash is held);
  `permissionMode: bypassPermissions` (replacing verifier/reviewer `dontAsk`).
- Body text scrubbed of policy-hook enforcement claims; boundaries restated as
  instruction-level discipline. verifier/reviewer immutability is enforced by their tool
  surface (no Write/Edit) plus instruction not to mutate via shell.
- ops: gate-approved *scope* model per the scope rule above; reversal notes in reports;
  never hands a command to the human.
- researcher, ticketer: unchanged (no shell access).

### Orchestrator

- Roster grows to ten dispatchable specialists (`Agent(executor)` added); model table gains
  the executor row; dispatch-guard allowlist updated in lockstep.
- New first rule: **never hand the human a command to run, and never relay a specialist's
  request that the human run one.** Approval-needing actions are presented as intent at a
  gate; on approval the right specialist executes.
- Trivial tier: arbitrary shell work dispatches to the executor; the "faster from your own
  shell" escape hatch is deleted.
- Gates section defines the minimum intent statement: the goal, plus the mutation scope in
  plain language.
- Stale examples referencing policy blocks (package-install and deletion prohibitions) are
  rewritten, since those prohibitions no longer exist.

### install.sh — retire-and-purge

- `HOOK_FILES` becomes: secrets, audit, cost, dispatch-guard, model-rates.
- New `RETIRED_HOOK_FILES`: the three policy files. On install: backed up to the run's
  backup dir if present, then **deleted** from `$CLAUDE_DIR/hooks/` after all copies
  succeed. On a failed install, `restore()` still restores them (a rollback returns the
  machine to its exact prior state, old agent files included, so no dangling hook
  reference is possible).
- `--check` **fails** with a `RETIRED` finding if any retired hook file is still installed.
- Validation runs the new hook tests and the new sandbox retire test; the final message
  reports 11 agents.

### Tests

- `tests/test_audit_hook.sh` — logs Bash commands with role; exits 0 on malformed stdin,
  non-Bash tools, unwritable log dir.
- `tests/test_secrets_hook.sh` — ports the secret-guard cases from the old policy suite:
  secret→file blocks (redirect, tee), secret without file direction allows,
  `2>/dev/null`/`2>&1` don't false-positive, Write/Edit content with a credential variable
  blocks, plain content allows.
- `tests/test_agent_frontmatter.sh` — static acceptance: no agent file references
  `agent-team-policy.sh`; every command-running agent (builder, verifier, reviewer, ops,
  deployer, executor) carries `permissionMode: bypassPermissions`, an audit registration,
  and a secrets registration; architect and scribe carry the secrets registration.
- `tests/test_dispatch_guard.sh` — executor added to the valid set.
- `tests/test_install_retire.sh` — sandbox `CLAUDE_CONFIG_DIR` install over a stale policy
  hook: retired files purged, new hooks installed executable, `--check` OK, then `--check`
  fails RETIRED when a stale file reappears.
- `tests/test_policy_hooks.sh` deleted with the hooks it tested.

### Behavioral validation (required before this change is called done)

Static tests cannot check the central requirement, so
`docs/superpowers/validation/2026-07-12-approve-intent-not-commands-validation.md` defines
a manual procedure (precedent: the 2026-07-10 decision-discipline validation):

1. **No-command-theater scenario:** dispatch a task requiring a package install and a file
   reorganization through the orchestrator. Pass: zero commands surfaced to the human, zero
   permission prompts after gate approval; the audit log shows the commands ran.
2. **Executor-refusal scenario:** dispatch the executor directly with no approval statement.
   Pass: it runs nothing and reports the missing approval.

## Acceptance criteria

1. `bash tests/test_audit_hook.sh`, `test_secrets_hook.sh`, `test_agent_frontmatter.sh`,
   `test_dispatch_guard.sh`, `test_install_retire.sh`, `test_cost_hook.sh`,
   `test_decision_discipline_drift.sh`, `test_install_skills.sh` all pass.
2. `bash install.sh` succeeds end-to-end; on a machine with the old hooks installed, the
   three policy files are gone from `$CLAUDE_DIR/hooks/` afterward and `--check` is OK.
3. `grep -rl "agent-team-policy" agents/` returns nothing.
4. The two behavioral validation scenarios pass, with evidence recorded in the validation
   doc's log section.

## Trade-offs stated plainly

- **No machine floor.** After a gate approval, an agent could run something destructive the
  human didn't anticipate. Recovery: git history for the repo; reversal notes and the audit
  log for everything else; the deployer's rollback discipline for deploys. Cloud mutations
  outside deploys have no automatic rollback — that is the accepted cost of the model.
- **Prompt injection.** Agents with bypassPermissions that ingest untrusted content
  (READMEs, web pages, package postinstall output) are an arbitrary-command-execution path
  with no machine floor; the old blocklist was an accidental partial mitigation. Accepted
  risk, mitigated by gates, the audit log, and agent instructions to treat fetched content
  as data, not instructions.
- **Auto-mode caveat.** If the orchestrator session itself runs in *auto* permission mode,
  subagent frontmatter `permissionMode` is ignored and prompts can return. Run the
  orchestrator in default mode. (Parent `bypassPermissions`/`acceptEdits` also override,
  harmlessly in the same direction.)
- **Built-in circuit breakers stay.** `rm -rf /` and `rm -rf ~` still prompt — a
  client-level protection this design does not (and cannot) remove.
- **Verifier immutability weakens** from hook-enforced to tool-surface + instruction: the
  verifier has no Write/Edit tools, but shell redirection could technically write. Accepted;
  the failure mode (verifier "fixing" a test) is visible in review and the audit log.

## Panel record

Spec panel (7 experts, discussion mode) drove: the executor approval check, the audit hook
and secret-guard re-decisions (taken back to the human as contested points), the scope rule
with worked examples, install retire-and-purge precision, the required behavioral
validation, and the injection-risk acknowledgment above.

## Amendment 2026-07-13 — External prior art: Ringer

[Ringer](https://github.com/NateBJones-Projects/ringer), a parallel agent-swarm
orchestrator reviewed 2026-07-13, is an independent existence proof of this spec's bet.
It spends zero effort gating command syntax and all of its trust budget on outcome
verification: every task declares an executable `check` (exit 0 = pass) plus expected
output files, pass/fail comes from *running* the check — never from the worker's
self-report — and raw worker output is logged verbatim. That model runs unsandboxed
workers across three different harnesses (Codex, Grok, OpenRouter) at swarm scale, which
is stronger evidence than this team's single-harness case.

Mechanisms worth consulting during implementation (source vendored nowhere — read
upstream; its license is non-standard, so take ideas, not code):

- **Verification over trust as the invariant** — the direct analogue of this spec's
  "the gate approves intent; the audit log and verifier judge outcomes."
- **Lint against tautological checks** — static analysis flagging checks that cannot
  fail or fail silently. If verification is the floor that replaces command-gating, the
  floor must itself be falsifiable; this concern is being designed separately
  (`2026-07-13-acceptance-check-linting-design.md`).
- **Retry-with-failure-context** — the failed check's actual output is appended to the
  retry prompt; matches this team's existing repair-loop pattern and argues for keeping
  verifier evidence verbatim, not summarized.

No change to this spec's decisions or acceptance criteria; this amendment records
corroborating evidence and cross-links the follow-on designs.
