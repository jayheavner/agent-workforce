# Surface compatibility

## Guarantees by surface

| Capability | Claude Code plugin | ChatGPT Work/web | ChatGPT desktop Codex | Codex CLI/IDE |
|---|---|---|---|---|
| Bundled workflow skills | Yes | Yes | Yes | Yes |
| Eleven-role routing contract | Yes | Reduced sequential fallback only after acceptance | Yes | Yes |
| Real specialist subagents | Yes | Account dependent, inherited settings | Built-in children exist, but the tested v2 API cannot select a custom profile | Surface dependent; companion dispatch always uses independent tasks |
| Per-role model and effort pins | Yes | No | Yes through direct or companion profile dispatch; not through the tested task-name-only child API | Yes through direct or companion profile dispatch |
| Custom local agent profiles | Claude agent definitions | No | Companion-installed under `~/.codex/agents/` | Companion-installed under `~/.codex/agents/` |
| Per-role mutation hooks | Enforced by the Claude integration | No equivalent guarantee | Hard command vetoes after hook trust; parent permissions may supersede sandbox defaults | Hard command vetoes after hook trust; parent CLI flags may supersede sandbox defaults |
| Exact workforce cost hook | Claude transcript format only | No | No | No |

## Required behavior

- Treat an explicit `$agent-workforce`, `@agent-workforce`, or plain-language request to use the workforce as authorization to delegate when the surface exposes subagents.
- Install user-level custom agent profiles only through the explicit `install-codex.sh` setup action, never as a hidden side effect of invoking the skill.
- On local Codex, require the exact named profile and its `WORKFORCE_PROFILE` completion marker. A task name alone is not a profile selector. If the collaboration tool exposes only task naming, use `bin/agent-workforce-dispatch`; missing profiles are not a reason to use a generic worker.
- Require role-policy hooks to be trusted before local mutating phases. Their exit-code vetoes are an enforcement boundary; prose instructions alone are not.
- In hosted ChatGPT Work, say `FULL PARITY UNAVAILABLE`: it cannot load the local profiles or hooks, and its subagents inherit the parent task's model and tools.
- In an explicitly accepted single-thread fallback, keep the narrow pause conditions and verification loop but label review independence as degraded.
- Do not invoke Claude-only scripts under `hooks/` for ChatGPT/Codex cost accounting or claim their audit logs cover ChatGPT/Codex actions.
- Codex specialist profiles use the shared role-policy scripts installed under `$CODEX_HOME/agent-workforce/hooks`. Trust only the reviewed definitions installed by this repository.
- Codex exposes model identity to hooks, but not stable per-dispatch effort, token, or credit totals. The profile pins effort; usage reporting remains task-level when the surface exposes it.
- Companion profile dispatch creates an independent Codex task rather than an in-thread child bubble. Disclose that UI/conversation limitation once; do not describe it as native subagent dispatch.
- Connector availability is account and workspace specific. Check that the required connector or MCP tool is actually callable before planning around Glean, Asana, cloud, identity, or secret-store access.
