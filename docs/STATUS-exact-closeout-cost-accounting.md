# STATUS: exact-closeout-cost-accounting

## Task
Replace the closeout cost table's blended estimate with exact per-session token accounting priced from a rates config, keeping the estimate as a fallback. Repo: ~/claude/ai-agent-team. Standard tier, full software route, local only (no deploy).

## Phases Completed
- Architect discovery + spec
- Implementation plan approved
- Builder: 13 tasks implemented TDD (commits d61598f..13c1fa0)
- Verifier: all 5 acceptance criteria passed with independent hand-derived math
- Reviewer (opus): returned approve-with-fixes

## Artifacts Produced
- Spec: `docs/superpowers/specs/2026-07-08-exact-closeout-cost-accounting-design.md`
- Amended spec+plan: dated 2026-07-09 (distinguishes corrupt vs. still-being-written files)
- Implementation commits: d61598f, 13c1fa0, 1130df5, 23a79e9, efa6587

## Key Discoveries
- Hook payload contains `session_id` and `transcript_path` for session identification.
- Transcripts are JSONL format with usage fields: `input_tokens`, `output_tokens`, `cache_creation_input_tokens` (5min/1hr split), `cache_read_input_tokens`.
- Model identifier is available at `.message.model` within transcripts.
- Subagent usage lives in separate sibling files under `<session-id>/subagents/`, enabling one-file-per-dispatch parsing with no incremental overhead.
- Log lines are duplicated per message ID and must be deduplicated.
- Rates verified for haiku, sonnet, opus, and fable models including cache multipliers.
- Reviewer found spec-internal contradiction: "self-heal on later fires" defeated by sticky-unavailable short-circuit allowed transient half-written sibling to pin session to fallback estimate.

## Amendment & Repair
Architect amended spec to distinguish genuinely-corrupt file (sticky unavailable) from still-being-written 0-byte/truncated-final-line file (skip, retry later). Builder repaired with commits 1130df5, 23a79e9, efa6587, adding partial-read fixtures, rate-precision guard in install.sh, UUID session_id path-confinement guard.

## Test Results
- All 5 acceptance criteria pass
- test_cost_hook.sh: passed=51, failed=0
- test_policy_hooks.sh: passed=191, failed=0
- install.sh and install.sh --check both exit 0
- Original fixture math exact: opus 0.061, sonnet 0.0555, grand 0.1165

## Next Phase
Awaiting final human gate. No deploy phase (local only).

## Open Questions Resolved
1. Orchestrator's own session usage: excluded per human approval
2. Web-search: count but do not price per human approval
