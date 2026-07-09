# AI Agent Team — Design

**Date:** 2026-07-07
**Status:** Approved design, pre-implementation
**Owner:** jheavner@cta.tech

## Purpose

A team of scoped Claude Code subagents covering the full range of Jay's work — software
design/spec/build/test/deploy, plus research, cloud ops, document writing, and Asana ticket
workflows. Each agent has a fixed role, a pinned model, and enforced permissions. An
orchestrator agent decomposes incoming work, dispatches specialists, and stops at human
gates between phases.

## Form factor

Plain agent definition files installed to `~/.claude/agents/` (user scope — available in
every project on this machine). Not a plugin: plugin-packaged agents ignore `hooks`,
`permissionMode`, and `mcpServers` frontmatter, which this design depends on. Plugin
packaging is an explicit non-goal for v1 (see Scope).

Source of truth is the git repo at `~/claude/ai-agent-team`. Installation copies files
into `~/.claude/`; nothing is edited in place there.

## Roster

| Agent | Default model | Effort | Role | Mutation rights |
|---|---|---|---|---|
| orchestrator | `claude-opus-4-8` | high | Triage, decompose, dispatch, enforce gates. Runs as the main session (see Orchestration) | None (read + dispatch only) |
| architect | `claude-fable-5` | high | Design, spec, plan — frontier reasoning lives here | Docs only (specs/plans) |
| builder | `claude-sonnet-5` | high | Implement per approved plan, TDD, commit | Code + local git; no deploy, no push to main |
| verifier | `claude-sonnet-5` | — | Run tests and acceptance checks | None (read + run) |
| reviewer | `claude-opus-4-8` | high | Code and security review | None (read only) |
| deployer | `claude-sonnet-5` | medium | Cloud deploys (SAM, Amplify, CDK) | Deploy commands only, each prompted |
| researcher | `claude-sonnet-5` | — | Web, Glean, codebase investigation | None |
| ops | `claude-sonnet-5` | high | AWS/Azure/Okta investigation and admin | Cloud reads free; mutations prompted |
| scribe | `claude-sonnet-5` | — | Reports, briefs, requirements, postmortems, status notes | Docs only |
| ticketer | `claude-sonnet-5` | — | Asana write/review/track | Asana via MCP; gated before filing |

Model IDs are pinned as full IDs deliberately: model updates are deliberate edits to
this repo (re-run install), never automatic. `install.sh` warns if the
`CLAUDE_CODE_SUBAGENT_MODEL` environment variable is set, since it silently overrides
every pin in this table.

Model policy: assignments follow `~/.claude/skills/model-picker/approved-models.yaml`
(`dispatchable_tiers`: frontier = Fable 5 / Opus 4.8; budget = Sonnet 5 / Haiku 4.5).
Ambiguous or hard-to-check work gets frontier; structured, reviewable work gets budget.
Frontier reasoning is concentrated in the **architect** (Fable 5), the one role whose
output quality most depends on it. The **orchestrator runs Opus 4.8, not Fable** —
its work (triage, routing, gate summaries) is structured judgment over specialist
reports, and the first shakedown proved the Fable-everywhere configuration
catastrophically mismatched to a small task: whole turns ran 11–19 minutes
dominated by over-weighted Fable dispatches, and the run exhausted the org's
monthly spend limit on a trivial CLI tool, with the orchestrator's own Fable
pricing applied to the session's largest and longest-lived context.
Opus 4.8 is state-of-the-art at exactly this long-horizon agentic
coordination, at half Fable's per-token price. The reviewer deliberately runs a
different model (Opus) than the builder (Sonnet) so review is not the builder's
model grading its own output.

**Effort** is the reasoning-depth control (`low`/`medium`/`high`/`xhigh`/`max`),
set per agent in frontmatter. `high` is the sweet spot for judgment work
(orchestrator, architect, builder, reviewer, ops); `xhigh` is deliberately avoided —
Fable/Opus at `high` already exceed prior-generation `xhigh`, and the shakedown's
overthink pattern (a 10-minute, 114k-token plan amendment) is exactly what `xhigh`
on routine work produces. The deployer runs `medium`: its work is procedural
(execute recorded commands, capture evidence, roll back on failure), spelled out in
its prompt. Four agents — verifier, researcher, scribe, ticketer — deliberately set
**no effort field**: they are the roles the orchestrator may downshift to Haiku 4.5
per dispatch, and Haiku rejects the effort parameter at the API level (Claude Code's
handling of a frontmatter effort combined with a Haiku override is undocumented, so
the pins are omitted rather than gambling a mid-pipeline dispatch failure on it).
They inherit the session's effort instead.

### Scaling down — dispatch-time model overrides, not duplicate agents

Each agent's frontmatter pins its **default**; the orchestrator's Agent tool carries
a per-invocation `model` parameter that overrides the pin (documented resolution
order: `CLAUDE_CODE_SUBAGENT_MODEL` env var > per-invocation parameter > frontmatter
> session model). This is the scale-down mechanism: one definition per role, tiered
per task by the orchestrator, which states its picks at triage so the human sees the
cost/depth plan up front. Effort has no per-invocation override — depth within a
dispatch is steered by the model tier plus explicit scope in the dispatch prompt.
The override table (who shifts where, and when) lives in `agents/orchestrator.md`.
An earlier fix attempt (`architect-lite`, a duplicate agent pinned to Opus) is
superseded by this mechanism and was removed: it fixed one role by file duplication,
couldn't generalize to ten roles, and split the architect's identity in two. What it
got right is preserved differently — the architect now preloads only
`superpowers:writing-plans` and invokes `superpowers:brainstorming`, `plan-review`,
and `ux-to-ui-design` situationally via the Skill tool (a UI skill is never again
loaded for a tool with no UI), and its prompt scales artifact size to the tier the
orchestrator declares in the dispatch.

### Skill preloads (frontmatter `skills:`)

- architect: `superpowers:writing-plans` (always); invokes `superpowers:brainstorming`, `plan-review`, and `ux-to-ui-design` situationally via the Skill tool per task tier — see Scaling down above
- builder: `coding-standards`, `superpowers:test-driven-development`, `secure-secrets`
- verifier: `superpowers:verification-before-completion`, `task-verification`
- reviewer: `code-review`
- deployer: `verify`
- ops: `secure-secrets`
- scribe: `writing-business-requirements`, `audit-requirements-document`
- ticketer: `write-ticket`, `review-ticket`, `task-verification`

Agents are the identity (model + permissions); skills remain the procedure. Roles invoke
additional skills situationally (e.g., architect runs `iv-define-system-map` for
system-scale interviews; reviewer runs the built-in `security-review`).

## Permissions — three layers

**Layer 1 — tool allowlists (`tools:` / `disallowedTools:` frontmatter).** A tool absent
from the list does not exist for that agent.

- orchestrator: Read, Glob, Grep, Agent, TaskCreate/TaskUpdate/TaskList, AskUserQuestion. No Edit/Write/Bash. Only the orchestrator holds the Agent tool.
- architect: Read, Glob, Grep, WebSearch, WebFetch, AskUserQuestion, Write/Edit (hook-restricted to `docs/`).
- builder: Read, Glob, Grep, Edit, Write, Bash (hook-restricted), NotebookEdit.
- verifier: Read, Glob, Grep, Bash (hook-restricted to non-mutating + test commands).
- reviewer: Read, Glob, Grep, Bash (hook-restricted to read-only git/diff/test commands).
- deployer: Read, Glob, Grep, Bash (hook-restricted to deploy + verification commands).
- researcher: Read, Glob, Grep, WebSearch, WebFetch, Glean MCP tools.
  (Subagents do not inherit session MCP servers — researcher and ticketer declare
  their servers explicitly via `mcpServers:` frontmatter.)
- ops: Read, Glob, Grep, Bash (hook-restricted cloud policy), WebSearch, WebFetch.
- scribe: Read, Glob, Grep, Write, Edit (hook-restricted to document paths), WebSearch, WebFetch.
- ticketer: Read, Glob, Grep, Asana MCP tools, AskUserQuestion.

**Layer 2 — per-agent PreToolUse hooks.** One shared policy script
(`~/.claude/hooks/agent-team-policy.sh`), parameterized by role, wired into each agent's
`hooks:` frontmatter. Exit code 2 blocks the call and returns the reason to the agent.
Cloud-command strategy is an **allowlist for every role** (block everything except
approved verbs), not a denylist — AWS CLI mutating verbs are too numerous and
service-specific to enumerate safely. Role policies:

- builder: no cloud CLI at all; block `sam deploy`, `amplify`, `cdk`, `terraform`; block `git push` to main/master (feature branches allowed).
  Examples: `git push origin main` → block; `git push origin feature/x` → allow; `sam build` → allow; `sam deploy` → block.
- verifier: block all file-mutating shell commands and all cloud CLI; allow test runners, linters, read-only git.
  Examples: `pytest` → allow; `git diff` → allow; `aws s3 rm …` → block; `rm -rf build/` → block.
- reviewer: allow only read-only commands (git log/diff/show, grep-class, test runs).
- deployer: allow the deploy toolchain (`sam`, `amplify`, `cdk`, `aws cloudformation|s3 sync` for deploy paths) plus read-only verification; block everything else.
- ops: allow cloud verbs matching `get-*|list-*|describe-*|head-*` (and Azure `show|list`); every other cloud verb blocks at the hook with instructions to surface the intended command to the human, who runs approved mutations through the gate.
- architect/scribe: Write/Edit allowed only under `docs/`, `plans/`, or the project's spec directories.
- all roles: block commands that redirect or interpolate known credential env vars (`$OKTA_TOKEN`, `$GODADDY_API_*`, `OP_SERVICE_ACCOUNT_TOKEN`, `*_API_KEY`, `*_SECRET*`, `*_PASSWORD*`) into files, and block writes of high-entropy token literals the same way the existing secure-secrets discipline defines them; only ops and deployer may invoke `op`.
- all roles: every hook decision appends one audit line — timestamp, role, command, allow/block — to `~/.claude/logs/agent-team-audit.log`, so any agent's actions (especially deployer) can be reconstructed afterward.

The hook test file (`tests/test_policy_hooks.sh`) encodes the must-block / must-allow
examples above per role and is the executable form of this policy.

**Layer 3 — permissionMode.**

- deployer, ops: `default` — hook-allowed mutations still prompt the human.
- reviewer, researcher, verifier: `dontAsk` — nothing they can do is dangerous; keep them fast.
- others: `default`.

Known caveat (verified against docs): a parent session in `bypassPermissions`/auto mode
overrides subagent `permissionMode`. Layer 2 hooks are the backstop that holds
regardless of session mode.

## Orchestration

**Invocation.** The orchestrator runs **as the main session** — `claude --agent
orchestrator` (or switching agent in-session) — not as a dispatched subagent. This is
load-bearing: gates require stopping mid-task to interact with the human, and a
dispatched subagent returns only a final result. Running main-session also makes the
`Agent(role)` allowlist in its frontmatter enforceable. Its `description:` is written
narrowly so ordinary sessions never auto-delegate to it; the team is opt-in per task.

**Triage.** Before the first dispatch, the orchestrator classifies the task —
ambiguity, novelty, blast radius, size — into a tier and states the tier, route, and
per-dispatch model picks in one paragraph the human can override. **Small** (clear
requirements, established pattern, contained blast radius): one architect dispatch
on Opus producing a short combined spec+plan, one gate, then build → verify → review
→ final gate. **Standard**: the full route below with separate spec and plan gates.
**Large/high-risk**: full route plus a researcher pre-phase for open factual
questions, architect told to go deep, reviewer optionally upshifted to Fable for
security-critical surfaces. Mis-triage is corrected by re-tiering mid-task, not
pushed through.

**Routes.**

- Software: architect (design+spec) → GATE → architect (plan) → GATE → builder (TDD) → verifier → reviewer → GATE → deployer → verifier (smoke). Small tier collapses the two design phases and gates into one. A failed smoke check triggers the deployer's rollback procedure — redeploy the previous known-good version (`sam deploy` of the prior artifact, Amplify redeploy of the prior build) — then escalation to the human with the failure evidence. The deployer records the current known-good identifier before every deploy so rollback has a target.
- Research/ops/document/ticket: researcher or ops gathers → scribe or ticketer produces → GATE before anything outward-facing (filed ticket, sent report, cloud mutation). Scaled the same way: a single-fact lookup is a Haiku researcher dispatch, not an investigation. A bare factual question is the smallest case of this route — the orchestrator never answers checkable facts from training memory, caveat or not (rule added after the second shakedown, where it answered a Python-version question from memory instead of dispatching, and the answer was stale).
- Amendments (mid-build spec/plan fixes): a delta-only architect dispatch on Sonnet (mechanical) or Opus (judgment) — page-scale in-place edits, never a re-run of the design process. The first shakedown spent 114k Fable tokens and 9 minutes swapping pytest for unittest; this rule exists so that never recurs.

**Gate behavior.** At each GATE the orchestrator stops, presents the artifact with a
plain-language summary and recommendation, and waits. Approval at one gate never implies
the next; the deploy gate is always explicit.

**Closeout cost report.** The final gate includes a per-dispatch accounting table
(agent, model, tokens, total, estimated cost). Mechanism: background-dispatch
completion notifications carry a usage block with the subagent's token count —
synchronous dispatch results carry no usage at all (verified empirically), so the
orchestrator dispatches in the background by default and records the counts as they
arrive. Cost is an estimate (tokens × a blended per-model rate held in
`agents/orchestrator.md` with the list prices and an ~85/15 input/output
assumption), always labeled as such: it excludes the orchestrator's own session
usage and cache discounts. Exact spend remains the human's `/usage` surface; an
exact in-closeout figure would need a transcript-parsing hook (see Scope).

**Failure handling.** Verifier/reviewer findings return to the builder with findings
attached; maximum two repair loops, then escalate to the human. Any agent hitting
unexpected state (missing credentials, broken environment) stops and reports rather than
improvising — the stop-and-alert rule is in every agent's prompt.

**Runaway control.** Every specialist sets `maxTurns` in frontmatter (generous for
builder/architect, tight for verifier/reviewer); an agent that hits its cap returns
partial work and the orchestrator escalates rather than re-dispatching blindly.

**Artifacts.** Specs to `docs/superpowers/specs/`, plans to `docs/plans/`. The
orchestrator has no Write tool by design, so the per-task `STATUS.md`-style handoff
note is written by the **scribe** at the orchestrator's direction — dispatched on
Haiku, at gates and at completion only (the first shakedown's one-dispatch-per-phase
cadence produced ten scribe runs for one small task), folding multiple completed
phases into one update — so interrupted work resumes cleanly.

## Repository layout

```
~/claude/ai-agent-team/
  agents/           # ten *.md agent definitions (source of truth)
  hooks/
    agent-team-policy.sh
  tests/
    test_policy_hooks.sh   # feeds each role's hook must-block / must-allow commands
  install.sh        # validate → back up → copy into ~/.claude/
  README.md
  docs/superpowers/specs/  # this document
```

`install.sh` follows the config-safety rule: validate in a temp location (`bash -n`,
frontmatter lint), back up any file being replaced, install only after validation, and
restore the backup on failure. Validation also fails the install if any `skills:` entry
in any agent file does not resolve to an installed skill (renamed skills must break
loudly, not degrade silently), and warns if `CLAUDE_CODE_SUBAGENT_MODEL` is set in the
environment or shell config.

## Testing the team

1. **Hook policy tests** (automated): `tests/test_policy_hooks.sh` runs every role's
   must-block and must-allow command list against the policy script and fails on any
   miss. These run before every install.
2. **Shakedown** (manual, once after first install): one small disposable end-to-end
   task through the full software route, confirming each gate fires, each agent stays in
   its lane, and handoffs carry sufficient context. Real work only after shakedown.

## Scope — v1

In: ten agent definitions, policy hook script + tests, install script, README, this spec.
Out (deliberate follow-ons): plugin packaging, per-agent persistent `memory:` tuning,
remote/managed-agent deployment, exact per-session cost accounting (a
transcript-parsing PostToolUse hook summing per-request input/output/cache usage —
the closeout's estimate table is the shipped v1). (Haiku downgrades, originally
deferred, shipped as the dispatch-time override mechanism — see Scaling down.)

**Known limitation — the Bash policy hook is a best-effort denylist on command
TEXT, not a real shell parser.** It matches regex patterns against the raw command
string; it does not tokenize or evaluate the shell grammar. A sufficiently obfuscated
command — unusual quoting, no-space fusing, base64-encoded payloads decoded and
`eval`'d, command names assembled from environment variables, or other indirection —
can defeat it, and this is accepted rather than chased with further regex iteration.
The design's actual security boundary is the human-in-the-loop `permissionMode` layer
(Layer 3) for roles in `default` mode, where hook-allowed mutations still prompt the
human. The read-only roles (verifier, reviewer, researcher — `dontAsk` mode) rely on the
hook layer more heavily specifically because they are expected to need no mutation
capability at all, not because the hook is airtight.
