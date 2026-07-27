# Status — dead-orchestrator reconcile (issue #8)

## Outcome

Implemented and verified on main; pushed; issue #8 closed. A headless `claude -p` orchestrator that dies mid-closeout (exits 0 after deliverables commit but before the cost table prints, firing no Stop hook) is no longer silent — the next session start surfaces a `reconcile:` warning.

## What shipped

`reconcile_lines(payload)` in `hooks/session_start.py`. At each session start it inspects the single most-recent prior transcript for the project (siblings of the current transcript_path, current excluded by abspath, highest mtime) and warns when it shows specialist dispatches (`scan_transcript` total > 0) but its final message carries neither `## Cost report` nor `WORKFORCE_PAUSE: HUMAN_DECISION`. Reuses `scan_transcript`/`COST_MARKER` from `agent_team_closeout` (same import idiom as debug_run_archiver). Fail-open (try/except in main(), always exits 0), read-only, zero new dependencies.

## Empirical grounding (before design)

Dead session 1b8846ff — last real assistant text "Now the cost report. Locating my transcript to run the reporter." then an isApiErrorMessage record; 61 WORKFORCE_REPORT markers + subagents dir (dispatches present); NO archiver state marker and NO transcripts/<id> branch — confirming no Stop or SessionEnd hook evaluated it.

## Evidence

Red-first suite of 10 tests authored by a separate test-author (commit 099b2fe) before implementation; builder made them green without editing them (aa08554). Fresh verifier: 12/12 mechanical ACs PASS, `Ran 25 tests ... OK`, imports exactly `['agent_team_closeout','json','os','subprocess','sys']`, live-payload exit 0, plus independent red-green regression against pre-fix code. Reviewer (fidelity + AC-13 judgment): SHIP.

## Decisions made and disclosed

- **Candidate (2) launcher-side `-p` check scoped OUT:** `bin/agent-workforce` runs an interactive TUI, never invokes `claude -p`, so it owns no headless runs to inspect. Candidate (1) is the whole fix.
- **Warning asserts observable STATE, not the cause "died":** the same signature also arises from an enforcement-cap allow, a stale-read allow, and an operator-closed interactive session (plan-critique finding, folded before build).
- **Design plan committed** under docs/superpowers/plans/ per repo convention.

## Residual limitation

Detection is deferred to the next session start, never real-time; only the final report/telemetry is lost while committed deliverables stand; single-most-recent-prior discovery means a plain later session can mask an older dead one — the deliberate anti-nag trade. (Also recorded in docs/superpowers/specs/2026-07-26-checks-balances-completion-drive.md)

## Commits

On main, pushed; HEAD bf0405c:
- 099b2fe tests
- aa08554 fix
- 1c903c7 spec residual
- bf0405c plan

Issue #8 CLOSED with an evidence comment.
