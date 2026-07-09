# STATUS: exact-closeout-cost-accounting

## Task
Replace the closeout cost table's blended estimate with exact per-session token accounting priced from a rates config, keeping the estimate as a fallback. Repo: ~/claude/ai-agent-team. Standard tier, full software route, local only (no deploy).

## Phases Completed
- Architect discovery + spec

## Artifacts Produced
- Spec: `docs/superpowers/specs/2026-07-08-exact-closeout-cost-accounting-design.md`

## Key Discoveries
- Hook payload contains `session_id` and `transcript_path` for session identification.
- Transcripts are JSONL format with usage fields: `input_tokens`, `output_tokens`, `cache_creation_input_tokens` (5min/1hr split), `cache_read_input_tokens`.
- Model identifier is available at `.message.model` within transcripts.
- Subagent usage lives in separate sibling files under `<session-id>/subagents/`, enabling one-file-per-dispatch parsing with no incremental overhead.
- Log lines are duplicated per message ID and must be deduplicated.
- Rates verified for haiku, sonnet, opus, and fable models including cache multipliers.

## Next Phase
Awaiting human approval at spec gate, then implementation plan.

## Open Questions for Human
1. Exclude orchestrator's own session usage from the exact table, or include it?
2. Web-search and web-fetch requests: acceptable to count but not price, or should we look up rates and add that cost?
