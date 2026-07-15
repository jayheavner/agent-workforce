# ChatGPT and Codex parity contract

Status: 2026-07-14

This document defines what “feature parity” means for the Claude Agent Workforce on OpenAI surfaces. It separates the local Codex implementation from hosted ChatGPT Work because those products expose different controls.

## Outcome

Local Codex in the ChatGPT desktop app or bundled CLI now has a high-parity companion implementation consisting of:

- the `agent-workforce` plugin skill;
- 23 named custom-agent profiles covering every default, downshift, and upshift;
- 23 equivalent top-level profiles for direct conversations and non-interactive phase dispatch;
- pinned GPT-5.6 model and reasoning-effort settings;
- full specialist role contracts generated from the Claude agent definitions;
- hard-veto `PreToolUse` policy hooks for model mismatches, forbidden shell commands, forbidden file edits, and nested specialist dispatches;
- a pinned Sol/High CLI orchestrator, direct-agent launcher, and marker-validating dispatcher;
- the original routing, gates, repair loops, spec criticism, gap handling, and evidence closeout.

The companion profiles are required because Codex custom agents live under `~/.codex/agents/` or project `.codex/agents/`, while plugin bundles distribute skills, hooks, apps, MCP configuration, and assets—not user-scoped custom-agent files. See [OpenAI’s custom-agent documentation](https://learn.chatgpt.com/docs/agent-configuration/subagents#custom-agents) and [plugin structure](https://learn.chatgpt.com/docs/build-plugins#plugin-structure).

## Parity matrix

| Capability | Claude Code | Local Codex implementation | Status |
|---|---|---|---|
| Eleven named roles | Native Claude agent definitions | Named direct-launch and custom-agent profiles, including two read-only debugger variants | Parity outside the current in-thread selector gap |
| Full role instructions | Agent Markdown bodies | Deterministically embedded from the same bodies | Parity |
| Default model pins | Opus/Sonnet | Sol/Terra workload equivalents | Functional parity |
| Cheap downshifts | Haiku | Luna/Low profiles | Functional parity |
| Deep upshifts | Fable or Opus | Sol/Max or Sol/Extra High profiles | Functional parity |
| Builder/reviewer separation | Sonnet builder, Opus reviewer | Terra builder, Sol reviewer | Parity |
| Stronger distinct spec critic | A different higher Claude tier when available | Terra/Max is distinct from Sol but not a higher capability tier | Partial; disclosed at gate |
| Reasoning-effort pins | Agent frontmatter | `model_reasoning_effort` in each direct profile | Parity for companion-dispatched specialists |
| Main orchestrator pin | Claude agent launch | Sol/High via CLI profile; manual composer selection in desktop | CLI parity; desktop manual prerequisite |
| Per-role shell policy | Blocking Claude hooks | Blocking Codex `PreToolUse` exit-code hooks | Parity after hook trust |
| Per-role write policy | Tool allowlist plus hooks | Sandbox defaults plus blocking patch/shell hooks | High parity; parent permissions can supersede sandbox defaults |
| Specialist cannot spawn agents | Tool deny list | Direct specialist profile instructions, hook veto, and `agents.max_depth = 1` | High parity |
| In-thread named-profile selection | Native agent type selector | Current ChatGPT/Codex team tool accepts a task name but no profile selector | Not available in the tested v2 host |
| Per-role tool allowlist | Native allowed/disallowed tools | No equivalent documented built-in allowlist for local custom agents; hooks veto dangerous tools | Partial |
| Hard `maxTurns` per role | Agent frontmatter | No documented per-agent turn limit for ordinary spawned agents | Not available |
| Exact per-dispatch token/cost report | Claude transcript hook and rate table | No stable per-subagent usage payload or credit-price attribution | Not available |
| Hosted ChatGPT Work | Not applicable | Cannot load local profiles or local role hooks | Full parity unavailable |

## Chosen OpenAI mapping

The complete machine-readable map is `codex/model-policy.json`.

- Claude Haiku workload → GPT-5.6 Luna, usually Low.
- Claude Sonnet workload → GPT-5.6 Terra, Medium or High.
- Claude Opus workload → GPT-5.6 Sol, High.
- Claude Fable workload → GPT-5.6 Sol, Max.

OpenAI describes Sol as the model for complex, open-ended work, Terra as the pragmatic all-rounder, and Luna as the model for clear repeatable tasks. OpenAI also exposes Low, Medium, High, Extra High, and Max reasoning levels. See [Models](https://learn.chatgpt.com/docs/models) and [Subagents: choosing models and reasoning](https://learn.chatgpt.com/docs/agent-configuration/subagents#choosing-models-and-reasoning).

This is a workload-equivalence policy, not a claim that OpenAI and Anthropic models are semantically identical.

## Irreducible gaps and why

### This machine's in-thread collaboration API does not select custom profiles

The current ChatGPT desktop runtime (`codex-cli 0.144.2`, tested 2026-07-14) exposes the v2 collaboration tool with `task_name`, not a custom-agent/profile field. Two live probes showed the consequence: the requested child was created with `agent_role: null`, inherited the parent `gpt-5.6-sol`/High runtime, and did not load the requested developer instructions or role hook. Merely naming the task after a profile does not select that profile.

The repository therefore does not claim that the built-in child thread is a pinned workforce specialist on this host. Instead, `bin/agent-workforce-dispatch` starts the requested role as an independent Codex task through its top-level config profile and fails if the exact profile/model/effort marker is absent. A live direct-profile test loaded Luna/Low with the researcher read-only sandbox, and a Terra/High builder test executed the installed hook and wrote `role=builder tool=Bash decision=allow detail=pwd` to the audit log.

This preserves the functional phase contract, pinned model and effort, role instructions, sandbox, and hook. It cannot preserve the native in-thread child bubble, shared conversation object, or built-in child lifecycle UI. Only OpenAI can close that tool-schema/routing gap. The documented custom-agent files remain installed and registered so a future runtime that exposes profile selection can use them without another migration.

### Hosted ChatGPT Work cannot be full parity

Hosted Work subagents use the parent task’s hosted tools and model/intelligence selection. It does not load files from `~/.codex/agents/`, local Codex sandboxes, or local policy hooks. The plugin skill can preserve routing and gates there, but it cannot truthfully claim pinned specialist models or hard role isolation. OpenAI documents hosted Work and local Codex permissions separately in [Subagents: approvals and sandbox controls](https://learn.chatgpt.com/docs/agent-configuration/subagents#approvals-and-sandbox-controls).

The workforce therefore stops with `FULL PARITY UNAVAILABLE` on hosted Work unless the user explicitly accepts reduced mode.

### A desktop plugin cannot set the parent composer model

Custom-agent files pin spawned specialists, but the main orchestrator remains the parent task. The ChatGPT desktop app selects that parent model and effort beneath the composer. Plugins do not expose a setting that changes it after task creation. The CLI can pin both values at launch, so `bin/agent-workforce-codex` uses the installed Sol/High profile. See [OpenAI model selection](https://learn.chatgpt.com/docs/models).

### Parent permission choices can supersede child defaults

OpenAI documents that subagents inherit the parent sandbox and that live parent permission overrides are reapplied to children even when a custom-agent file has different defaults. The role hooks still reject prohibited tool calls, but the plugin cannot promise that a profile will loosen a parent sandbox enough to perform an authorized operation. See [Subagents: approvals and sandbox controls](https://learn.chatgpt.com/docs/agent-configuration/subagents#approvals-and-sandbox-controls).

### No hard ordinary-subagent turn limit is documented

Codex exposes `agents.max_threads`, `agents.max_depth`, and a CSV-worker runtime limit. It does not document a per-profile equivalent of Claude’s `maxTurns` for normal spawned agents. The Codex profiles carry the same stop/report instructions, but this is behavioral rather than a hard runtime limit. See [Subagents: global settings](https://learn.chatgpt.com/docs/agent-configuration/subagents#global-settings).

### Exact per-dispatch cost cannot be reproduced reliably

Codex hooks expose the active model, session, transcript path, and tool lifecycle. OpenAI explicitly says the transcript format is not stable. The supported non-interactive event stream reports task usage, and workspace analytics are aggregated; OpenAI warns against treating aggregated analytics as exact per-workflow cost attribution. ChatGPT credit consumption also does not provide a stable public per-token dollar-rate contract equivalent to this repository’s Claude rate table. See [Hooks: common input fields](https://learn.chatgpt.com/docs/hooks#common-input-fields) and [ChatGPT Work usage and cost](https://learn.chatgpt.com/docs/enterprise/work-admin-faq#usage-and-cost).

The Codex workforce records the exact intended profile, model, and effort for every dispatch and fails closed on a model mismatch when the hook runs. It does not fabricate per-agent token or dollar totals.

## Installation contract

Every local machine needs both parts:

```bash
codex plugin marketplace add jayheavner/agent-workforce
codex plugin add agent-workforce@agent-workforce
bash install-codex.sh
```

Then start a new task. In CLI, use `./bin/agent-workforce-codex`. In the desktop app, select Sol/High, invoke `$agent-workforce`, and trust the reviewed Agent Workforce hooks through `/hooks` before a mutating phase.

Start a direct specialist conversation with:

```bash
./bin/agent-workforce-codex --agent agent_workforce_researcher_fast
```

Run one independently pinned phase non-interactively with:

```bash
./bin/agent-workforce-dispatch agent_workforce_reviewer "Review the current diff against the approved plan."
```
