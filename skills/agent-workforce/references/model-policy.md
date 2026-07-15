# Codex model and effort policy

Use these named profiles for every local Codex specialist dispatch. The companion installer places custom-agent definitions under `~/.codex/agents/` and direct-launch equivalents under `~/.codex/*.config.toml`; the plugin alone cannot distribute that user-scoped configuration.

## Parent orchestrator

Run the main task on `gpt-5.6-sol` at `high` effort. `bin/agent-workforce-codex` enforces this in the CLI through the installed `agent-workforce` Codex config profile. In the ChatGPT desktop app, select Sol and High before starting the task; a plugin cannot change the parent composer model after the task starts.

## Specialist profiles

| Role and purpose | Required profile | Model | Effort |
|---|---|---|---|
| Architect, default | `agent_workforce_architect` | `gpt-5.6-sol` | high |
| Architect, mechanical amendment | `agent_workforce_architect_fast` | `gpt-5.6-terra` | high |
| Architect, novel or multi-system design | `agent_workforce_architect_deep` | `gpt-5.6-sol` | max |
| Builder, default | `agent_workforce_builder` | `gpt-5.6-terra` | high |
| Builder, unfamiliar work or second repair | `agent_workforce_builder_deep` | `gpt-5.6-sol` | extra high |
| Debugger, default symptom diagnosis | `agent_workforce_debugger` | `gpt-5.6-terra` | high |
| Debugger, repeated symptom or cross-system failure | `agent_workforce_debugger_deep` | `gpt-5.6-sol` | high |
| Verifier, default | `agent_workforce_verifier` | `gpt-5.6-terra` | medium |
| Verifier, one obvious smoke check | `agent_workforce_verifier_fast` | `gpt-5.6-luna` | low |
| Reviewer, default code review | `agent_workforce_reviewer` | `gpt-5.6-sol` | high |
| Reviewer, docs-only or trivial diff | `agent_workforce_reviewer_fast` | `gpt-5.6-terra` | high |
| Reviewer, security-critical work | `agent_workforce_reviewer_deep` | `gpt-5.6-sol` | max |
| Spec critic for a Sol-authored spec | `agent_workforce_spec_critic` | `gpt-5.6-terra` | max |
| Deployer | `agent_workforce_deployer` | `gpt-5.6-terra` | medium |
| Researcher, default | `agent_workforce_researcher` | `gpt-5.6-terra` | medium |
| Researcher, single fact | `agent_workforce_researcher_fast` | `gpt-5.6-luna` | low |
| Researcher, high-stakes synthesis | `agent_workforce_researcher_deep` | `gpt-5.6-sol` | high |
| Operations, default | `agent_workforce_ops` | `gpt-5.6-terra` | high |
| Operations, incident or unfamiliar failure | `agent_workforce_ops_deep` | `gpt-5.6-sol` | high |
| Scribe, default | `agent_workforce_scribe` | `gpt-5.6-terra` | medium |
| Scribe, status note | `agent_workforce_scribe_fast` | `gpt-5.6-luna` | low |
| Ticketer, default | `agent_workforce_ticketer` | `gpt-5.6-terra` | medium |
| Ticketer, comment or status update | `agent_workforce_ticketer_fast` | `gpt-5.6-luna` | low |

Treat Luna, Terra, Sol, and Sol-at-Max as the functional equivalents of the Claude integration's Haiku, Sonnet, Opus, and Fable tiers. This is a workload mapping, not a claim that the model families are identical.

## Selection and validation rules

- State the exact profile, model, and effort for every planned dispatch during triage.
- Route a symptom-shaped request to the default debugger before assigning a build tier. Use the deep debugger only for a second diagnosis of that symptom or a cross-system failure; there is no debugger downshift.
- Select the named profile through a native profile selector when one exists. When the active collaboration tool only accepts a task name, use `bin/agent-workforce-dispatch`; a matching task name on a generic child is not profile selection.
- Require the specialist's final `WORKFORCE_PROFILE` marker to match the requested profile. A missing or mismatched marker fails the phase.
- Use the distinct Terra-Max spec critic after a Sol architect. This preserves different-model criticism, but Terra is not stronger than Sol; disclose `critic strength: distinct model, lower capability tier` with the spec review result.
- If the architect ran the Terra downshift, use the default Sol reviewer for spec criticism.
- If local Codex does not expose the named profiles or the companion dispatcher, stop and direct the user to run `bash install-codex.sh`; do not substitute inherited-model subagents.
- ChatGPT Work hosted subagents do not expose local custom profiles. Label that surface `FULL PARITY UNAVAILABLE` and obtain explicit acceptance before using inherited-model hosted agents.
