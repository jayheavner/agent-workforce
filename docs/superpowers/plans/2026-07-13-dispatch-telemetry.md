# Dispatch Telemetry — Implementation Plan

**Spec:** `docs/superpowers/specs/2026-07-13-dispatch-telemetry-design.md` (Approved 2026-07-13,
D2 resolved: committed + install-validated `hooks/agent-model-defaults.json`).
**Plan-review conditions discharged here:** (1) every code task below is red-first;
(2) install.sh is verified via the sandboxed-HOME install test (`tests/test_install_skills.sh`,
invoked by the validate block) plus `bash -n` — never a live install from this plan;
(3) D2 was decided before this plan was written.

Execution note: worked to completion in one session at the human's direction
("work this to completion — don't stop until it's done"), so tasks are recorded
checked. Ordering below is the order the work actually ran.

## Tasks

- [x] **T1 — Discovery: `tool_input.model` presence.** The 2026-07-08 cost spec verified
  `tool_response` fields against a live transcript; `tool_input.model` has not been observed live.
  Per spec §2 the design is fail-open either way (absent → `requested_override: null`, drift `null`
  under override-only knowledge; the pin path via the defaults map still covers it). Hook-schema
  docs state PostToolUse receives the tool call's `tool_input` verbatim, and the Agent tool's
  `model` parameter is a documented input — treated as confirmed-by-contract, with the fail-open
  path as the backstop and shakedown scenario T11 as the live confirmation.
- [x] **T2 — RED: cost-hook tests.** Extend `tests/test_cost_hook.sh`: (a) a fire whose payload
  carries `tool_input.model: claude-fable-5` stamps `requested_override` on the fired dispatch's
  entry only (the non-fired sibling gets `null`); (b) a payload without the field →
  `requested_override: null`; (c) regression — the good-fixture totals stay exactly
  `0.061` / `0.0555` / `0.1165` and the resolved-model keys are unchanged (proves cost math
  untouched). Run: new assertions fail against the unmodified hook; all prior assertions pass.
- [x] **T3 — GREEN: hook change.** `hooks/agent-team-cost.sh`: read `tool_input.model // empty`;
  on each dispatch entry set `requested_override` — the fired dispatch gets the current value (or
  `null`), every other entry preserves its prior value (or `null`). No recognition rule, pricing,
  dedup, or sticky-marker change. Run T2 tests: all pass.
- [x] **T4 — RED: scoreboard test.** New `tests/test_scoreboard.sh` + `tests/fixtures/telemetry/`
  with hand-computed truth in the test header: first-try pass/fail split across sonnet/opus repair
  rows, a drift-true record, an `n/a` support-role row, one unknown-model record (quarantined), one
  malformed line (skipped, counted), empty-tree case. Fails: script does not exist.
- [x] **T5 — GREEN: `tools/agent-team-scoreboard.sh`.** bash + jq, read-only. Groups by
  (role, resolved_model, tier); emits n, first-try% (pass among `sequence=="first"`; `—` when the
  group has none), pass% (pass among verdict≠`n/a`; `—` when none), median cost (nulls excluded),
  drift count; `unattributed`/`skipped` footer lines; empty tree → header only, exit 0. Rates from
  `AGENT_TEAM_RATES` or `hooks/model-rates.json` beside the script's repo. All T4 assertions pass.
- [x] **T6 — `hooks/agent-model-defaults.json`.** Committed map `{schema:1, roles:{<name>:<pin>}}`
  for all ten agents, generated from `agents/*.md` frontmatter.
- [x] **T7 — `docs/telemetry/README.md`.** Record schema v1, field sources, `requested_model`
  resolution order (override → defaults map → null), quarantine rules, canonical-main counting
  rule, scribe rules (one file per session, append-only, never edit prior records).
- [x] **T8 — Agent instruction text.** `agents/orchestrator.md`: new `## Dispatch telemetry`
  section (spec §3 text: closeout-scribe extension, sequence/verdict definitions, trivial-tier
  exclusion, mandatory `telemetry:` final-gate line). `agents/scribe.md`: telemetry duty paragraph
  (join cost-file mechanical half to prompt verdict half; never invent a number).
- [x] **T9 — RED→GREEN: install.sh.** Add `agent-model-defaults.json` to `HOOK_FILES`
  (manifest/backup/restore/cleanup/install all key off the existing lists); validate block gains:
  `bash -n tools/agent-team-scoreboard.sh`, `bash tests/test_scoreboard.sh`, regenerate-and-compare
  of the defaults map against frontmatter (fail on mismatch), shape check every pin ∈
  `model-rates.json`. Red first: deliberately desync the map → validate fails; restore → passes.
- [x] **T10 — README.md.** "Dispatch telemetry" subsection under Cost accounting (record location,
  scoreboard usage, documented jq one-liner, defaults-map note) and one shakedown scenario.
- [x] **T11 — Verification gate.** All of: `tests/test_cost_hook.sh`, `tests/test_scoreboard.sh`,
  `tests/test_policy_hooks.sh`, `tests/test_dispatch_guard.sh`,
  `tests/test_decision_discipline_drift.sh`, `tests/test_gap_loop_text.sh`,
  `tests/test_install_skills.sh` (sandboxed-HOME full install) green; `bash -n` on changed shell.
  Live-run confirmation of `tool_input.model` and the end-to-end record flow is the added
  shakedown scenario (runs at next install, alongside the pending gap-loop shakedown).
- [x] **T12 — Commits.** Logical units: spec resolution + plan; hook + tests; scoreboard + fixtures
  + telemetry README; agent text; install.sh; README.

## Acceptance criteria

Spec §Acceptance criteria 1–6, with criterion 6's `bash install.sh` read as the validate path
exercised by the sandboxed-HOME install test per plan-review condition 2.
