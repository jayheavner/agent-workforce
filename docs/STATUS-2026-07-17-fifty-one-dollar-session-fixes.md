# STATUS: fifty-one-dollar-session-fixes

Tracks execution of `plans/2026-07-17-fifty-one-dollar-session-fixes.md` (T4–T17).
Each task appends its evidence below in order. Final delivery receipt at the end
covers the whole plan (T17 closes it out).

## T4-reconcile-installed-drift

**Diff summary** (`~/.claude/hooks/agent_team_closeout.py`, 571 lines, vs repo
`hooks/agent_team_closeout.py`, 442 lines — full diff read):

The installed copy adds three behaviors absent from repo HEAD:

1. **Blob preservation + restore-blob hints** (`_preserve_blob`, `blob` key on
   `_entry`, "Restore pre-task content of X with: git cat-file blob …" in the
   Stop block message, and a `vanished` baseline-dirt code path that emits
   restore instructions for paths that disappeared outside the session).
   **Rejected as-is** — the plan's fixed decision for T4 (line 115) names this
   exact mechanism and requires it be superseded by T7, not adopted. `git log
   --all -S"cat-file blob" -- hooks/agent_team_closeout.py` returns empty:
   this text has never existed in any commit of this repo, confirming fact 2.
   T7 replaces the "Task-owned" attribution and any restore guidance with
   truthful, baseline-scoped wording.
2. **`_breaker_block` / block-fingerprint loop-breaker** — after 3 identical
   consecutive Stop blocks with no progress, releases with
   `WORKFORCE_CLOSEOUT_RELEASED` and demands human review.
3. **`_fail_closed_with_limit`** — the same 3-strikes release pattern applied
   to the `main()` exception handler's fail-closed path (state/Git read
   failures).

Decision on (2) and (3): **not adopted in this task.** The fixed adoption rule
is "installed-only additions are adopted ONLY if they are pure improvements
that later tasks assume." No task in T4–T17 requires, references, or builds on
the loop-breaker/fail-closed-limit mechanism, so the "later tasks assume it"
condition is not met — adopting it here would be undecided scope expansion
beyond this plan's contract. Recorded here as a candidate for a future planned
task, not silently discarded: the installed profile copy currently running
has this protection and the repo does not, which is a real (if narrow) gap
until a task adopts it deliberately.

**`install.sh --check` (before this task, repo HEAD):**
```
check: STALE — repo agents/orchestrator.md changed since the last install; re-run install
check: STALE — repo hooks/agent-team-cost.sh changed since the last install; re-run install
check: DRIFT — /Users/jay/.claude/hooks/agent_team_closeout.py differs from the last install (hand-edited under ~/.claude/?)
check: FAIL — drift detected (lines above). Reconcile any hand edits back into the repo, then re-run 'bash install.sh'
```
Only `agent_team_closeout.py` reports DRIFT (installed copy hand-diverged from
what was last installed); the two STALE lines are expected repo-ahead-of-install
state from commits already on HEAD (`agents/orchestrator.md`,
`hooks/agent-team-cost.sh`) and are unrelated to this task's scope — `--check`'s
own logic (`install.sh:363,368`) confirms no other installed file diverges.

**Outcome:** repo `hooks/agent_team_closeout.py` is unchanged by this task —
the only installed-only behavior this plan's fixed rules speak to (blob/restore
hints) is explicitly rejected, not merged. `--check`'s DRIFT line clears once
T17 reinstalls from main, replacing the hand-edited profile copy with the repo
version (repo-wins, per the fixed rule). No other files diverge.

**Verification:** `python3 tests/test_agent_team_closeout.py` — 21 tests, green,
unchanged (no behavior touched). `bash install.sh --check` output captured above.

## T5-inflight-aware-stop

**Preflight:** confirmed via Claude Code docs (code.claude.com/docs/en/hooks)
that Stop payloads carry `transcript_path`. Inspected a real transcript JSONL
in this repo's own project directory to confirm the pairing shape: an
`assistant`-typed line's `message.content[]` holds a `tool_use` block with
`name: "Agent"` and an `id`; the paired `user`-typed line's
`message.content[]` holds a `tool_result` block whose `tool_use_id` matches.
An Agent dispatch with no later matching `tool_result` is in flight.

**Implementation:** `_inflight_dispatches(transcript_path) -> int` scans the
JSONL for unresolved Agent `tool_use` ids; malformed lines are skipped,
missing/unreadable transcript returns 0 (fail-closed to prior strict
behavior). In `_stop`: inflight > 0 with a SHIPPABLE verdict blocks ("dispatch
in flight — a completion claim cannot be final"); inflight > 0 otherwise
allows with no receipt/uncommitted/cleanup demand, checked before all other
Stop logic. Added `WORKFORCE_WAITING: <n> dispatch(es) in flight` to
`agents/orchestrator.md` as the orchestrator's honest progress vocabulary
(the hook does not require it).

**Verification:** 3 new red→green tests added to
`tests/test_agent_team_closeout.py` covering the three executable examples
(waiting despite dirty tree, blocks once resolved, SHIPPABLE blocked while
in flight). `python3 tests/test_agent_team_closeout.py` — 24 tests, green.
`bash tests/test_closeout_hook.sh` — 24 tests green, 90% coverage.
`bash tests/test_decision_discipline_drift.sh` — PASS=3 FAIL=0.
`bash tests/test_agent_frontmatter.sh` — passed=31 failed=0.

## T6-serialize-mutating-dispatches

**Preflight:** confirmed via docs and direct transcript inspection (same
evidence as T5) that PreToolUse payloads carry both `transcript_path` and
`tool_input.prompt` for Agent dispatches.

**Implementation:** `hooks/agent-team-dispatch-guard.sh` gains
`GIT_SERIALIZED_ROLES="builder executor deployer"` (a new constant — does not
repurpose the closeout hook's `MUTATING_ROLES`, which serves baseline-capture
logic and includes `architect`/`scribe` instead). For a dispatch whose
`subagent_type` is in that set: the exact prompt line `PARALLEL_SAFE: no git
mutation in this dispatch` exempts it; otherwise the guard scans
`transcript_path` (same unresolved-tool_use/tool_result pairing jq logic as
T5) for any unresolved Agent dispatch whose `subagent_type` is also in the
serialized set, and blocks naming that role if found. Non-serialized roles
and dispatches with no serialized role in flight are unaffected. Added the
routing rule to `agents/orchestrator.md`'s Rules section with the exact
marker line.

**Verification:** 3 new red→green tests in `tests/test_dispatch_guard.sh`
(unresolved builder blocks executor; PARALLEL_SAFE marker allows; no
serialized dispatch in flight allows). `bash tests/test_dispatch_guard.sh` —
PASS=37 FAIL=0. Full closeout suite, drift test, and frontmatter test
re-verified green (orchestrator.md touched again). `shellcheck` not present
in this environment — recorded per Discretion; `bash -n` syntax check passed.
