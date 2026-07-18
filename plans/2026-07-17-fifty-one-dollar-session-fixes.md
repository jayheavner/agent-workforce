# Plan: $51-session fixes — agent-workforce framework hardening

execution-contract: 1
plan-id: 2026-07-17-fifty-one-dollar-session-fixes
status: v2 (approved for execution on handoff)
scope: the agent-workforce framework (this repository) ONLY. v2 removed tasks T1–T3, which
remediated the innovation-awards project — out of this plan's scope. Task IDs T4–T17 are
kept stable. innovation-awards appears below solely as incident evidence, never as a work
target; no task may touch that repository.

## How to execute this plan (read first)

You are executing a pre-decided contract. Every design decision is already made and recorded
here; do not reopen them. Work one task at a time, in order, TDD where a test seam exists.
For each task: run its Preflight checks, write the red test, implement to green, run the
task's verification, commit exactly the Commit intent, then move on. If an Escalation
trigger fires, stop that task, report the evidence, and continue with the next independent
task if one exists. Never expand scope beyond a task's named files without an amendment.

## Goal

Fix the agent-workforce framework generators that the 2026-07-17 "$51 session" exposed —
receipt spam, hook/finalizer races, false ownership attribution, unbounded spend,
wrong-specialist routing, missing entry-path verification, silent install drift, and
hand-authored accounting. The incident transcript ran this framework against the
innovation-awards project; that project is the evidence source for these failures and
nothing more. Every change in this plan lands in this repository.

## Architecture

The agent-workforce framework lives in `/Users/jay/claude/ai-agent-team` and installs into
the Claude profile (`~/.claude`) via `install.sh`, recording `~/.claude/agent-team-manifest.json`.
Enforcement is hook-based: `hooks/hooks.json` routes PreToolUse(Agent) → dispatch guard +
closeout `dispatch` mode, PostToolUse(Agent) → cost hook, SubagentStop → closeout
`subagent-stop`, Stop → closeout `stop`. The closeout hook keeps per-session state and lints
final receipts via `tools/lint_completion_claims.py`. Orchestrator behavior is prose policy
in `agents/orchestrator.md`. All changes stay inside these existing components — no
new subsystems.

## Tech stack

Python 3 (hooks, linter, tests via `tests/test_agent_team_closeout.py`), Bash + jq (guards,
cost hook, shell tests under `tests/`), Markdown agent contracts. No new dependencies.

## Global constraints

- policy:workspace-isolation (source: `~/.claude/skills/project-policy/SKILL.md`): "the
  project checkout or worktree selected when the orchestrator session starts is the task
  workspace… Run only one code-writing task in a checkout at a time." All work happens in
  a worktree of `ai-agent-team` (warden makes the shared checkout read-only to shells).
- policy:dependency-freshness: not applicable — this plan adds no dependencies.
- Security pass (pre-implementation): no secrets in code, logs, tests, or commit messages;
  hook inputs parsed fail-closed (keep the dispatch guard's existing jq-parse-or-block
  pattern); all new hook error text must not echo file contents, only paths.
- Git identities: pushes to `ai-agent-team` require the `jayheavner` gh account. Run
  `gh auth status` before any push and switch accounts explicitly.
- Conventional Commits. New code files stay under ~300 lines. No time estimates anywhere.

## Verified repository facts (basis for this plan — re-verify only what Preflight names)

1. `hooks/agent_team_closeout.py` (repo HEAD, 442 lines): `_stop` demands a receipt on every
   Stop unless the message contains `WORKFORCE_PAUSE: HUMAN_DECISION`; the uncommitted-changes
   check (lines ~316–330) labels every baseline-dirt diff "Task-owned"; it has no knowledge
   of in-flight dispatches. `MUTATING_ROLES = {"architect", "builder", "executor", "scribe"}`
   exists at line 18. State helpers `_load_state`/`_save_state` exist.
2. **Installed-copy drift:** `~/.claude/hooks/agent_team_closeout.py` is 571 lines, differs
   from repo HEAD, and contains "Restore pre-task content … git cat-file blob" text that has
   never existed in ANY commit of this repo (`git log -S` across all history is empty). The
   manifest claims commit 6ea4b3f. The running control system is an unmanaged fork.
3. `tools/lint_completion_claims.py`: `ENTRY` regex requires `- field: value` list items;
   `LEDGER_FIELDS` has 8 fields and no `cost-report`; `VALID_STATUS = {pass, fail, pending,
   unchecked, not applicable}`; BLOCK output names failing checks but shows no template.
4. `hooks/agent-team-dispatch-guard.sh`: fail-closed jq guard that only validates
   `subagent_type` against the ten specialists. Test seam: `tests/test_dispatch_guard.sh`.
5. `hooks/agent-team-cost.sh`: writes `~/.claude/logs/agent-team-cost/<cwd-slug>--<session>.json`
   with a per-dispatch `dispatches` map (model, tokens, requested model) and per-model
   rollups; family-prefix rate resolution and fail-open-per-record landed in 75c306d.
6. `agents/orchestrator.md`: build banner + manifest logic at line ~42; tier definitions
   (Trivial/Small/Standard/Large) at ~55–67; model table ~170–174; spec-critic rule at line
   355: critic runs "one tier stronger (`haiku < sonnet < opus < fable`)" — this is the rule
   that put Fable on bug-fix critiques ($11.18 of the $51).
7. innovation-awards (verified 2026-07-17): local main == origin/main at 363ff473;
   `docs/product/bugfix-plan-review-queue-layout-css.md` exists on NO commit of main — its
   only copy is commit 7528476d, sole commit of branch `fix/review-queue-layout-css`
   (parent 20578961, which IS on main). Nothing was deleted by a foreign session; the
   session's own committer ran while the shared checkout's HEAD was on that branch.
8. innovation-awards: stale worktree registered at
   `.claude/worktrees/screening-gibberish-human-review-c861de` (branch
   `claude/screening-gibberish-human-review-c861de`, 1f54f0a3) — the E2BIG contributor.
9. innovation-awards: `docs/telemetry/review-queue-issue-28-and-404-fix.csv` on main has a
   header + 6 rows, every cost/token field `null`, despite ~45 subagent transcripts that
   session. The $51 figure covered subagents only; the orchestrator's own usage is extra.
10. Test seams exist: `tests/test_agent_team_closeout.py`, `tests/test_completion_lint.sh`,
    `tests/test_dispatch_guard.sh`, `tests/test_cost_hook.sh`, `tests/test_install_skills.sh`.

# Tasks (all in this repository; work in a worktree; TDD)

## T4-reconcile-installed-drift

**Outcome:** the repo is the single source of truth again: every behavioral difference in
`~/.claude/hooks/agent_team_closeout.py` (571 lines) vs repo `hooks/agent_team_closeout.py`
(442 lines) is either committed to the repo (if it is behavior later tasks build on) or
explicitly rejected in the task report; `install.sh --check` runs clean after the plan's
final install.

**Acceptance mapping:** new finding "installed hook contains never-committed code" →
evidence: a written diff summary in the task report; the repo file after this task contains
every kept behavior; no other installed file diverges (`install.sh --check` output).

**Files:** Modify: `hooks/agent_team_closeout.py`. Read-only: `~/.claude/hooks/agent_team_closeout.py`.
Test: `tests/test_agent_team_closeout.py`.

**Interfaces/invariants:** decision, fixed: the **repo version's behavior wins** wherever
the two conflict; installed-only additions are adopted ONLY if they are pure improvements
that later tasks assume (per-path restore guidance is NOT adopted as-is — T7 replaces it).
Never edit the profile copy by hand; it gets replaced by T17's install.

**Executable example:** Given the installed copy emits "Restore pre-task content of X with:
git cat-file blob …" — When reconciliation completes — Then the repo file either contains a
committed, tested equivalent (superseded by T7's rules) or the report records "rejected:
restore-blob guidance replaced by T7".

**Preflight:** `diff ~/.claude/hooks/agent_team_closeout.py hooks/agent_team_closeout.py`
full read; `bash install.sh --check` current output (expect it to flag the drift — record
it); check whether OTHER installed hooks/tools also diverge (`--check` covers this).

**TDD/verification:** existing suite `python3 tests/test_agent_team_closeout.py` green
before and after; any adopted behavior gets its own test first.

**Discretion:** classifying individual diff hunks as adopt/reject within the fixed rule.

**Escalation:** the diff reveals installed behavior that later tasks in this plan contradict in a way
not already decided here; `--check` reveals divergence in files this plan does not touch.

**Commit intent:** `fix(closeout): reconcile installed-copy drift into the repo` — path:
`hooks/agent_team_closeout.py`, `tests/test_agent_team_closeout.py`.

## T5-inflight-aware-stop

**Outcome:** the Stop hook distinguishes "waiting on in-flight dispatches" from "claiming
done": when one or more Agent dispatches are unresolved in the session transcript, Stop is
allowed with no receipt demand, no uncommitted-changes demand, and no cleanup demand.

**Acceptance mapping:** incident findings — 67 receipts / 19 blocks, hook racing the
in-flight committer, `WORKFORCE_PAUSE: HUMAN_DECISION` misuse, status-note churn →
evidence: new tests below pass; the four behaviors are keyed off one function.

**Files:** Modify: `hooks/agent_team_closeout.py` (`_stop`, new `_inflight_dispatches`).
Test: `tests/test_agent_team_closeout.py`.

**Interfaces/invariants (fixed design):**
- `_inflight_dispatches(transcript_path) -> int`: parse the session JSONL transcript;
  count Agent `tool_use` blocks that have no matching `tool_result` — ground truth, no
  counters to leak. PreToolUse/SubagentStop event counters are NOT the mechanism.
- In `_stop`: if inflight > 0 → allow (exit 0, no block) BEFORE the uncommitted-changes
  check, the receipt lint, and cleanup checks. A SHIPPABLE verdict with inflight > 0 is
  still blocked ("dispatches in flight — a completion claim cannot be final").
- Unreadable/missing transcript → inflight = 0 (fail closed to today's strict behavior).
- Add `WORKFORCE_WAITING: <n> dispatch(es) in flight` to the orchestrator vocabulary
  (`agents/orchestrator.md`) as the honest progress line; the hook does not require it.

**Executable examples:** Given a transcript with one unresolved Agent tool_use and a dirty
tree — When Stop fires with no receipt in the message — Then the hook allows the stop.
Given the same transcript after the tool_result lands — When Stop fires with no receipt —
Then the hook blocks exactly as today. Given inflight=2 and a message containing
`shipment-verdict: SHIPPABLE` — Then block.

**Preflight:** confirm the Stop payload delivers `transcript_path` (inspect an existing
fixture in `tests/fixtures/` or the hook router's stdin contract); confirm the transcript
JSONL shape for Agent tool_use/tool_result pairing on a real session file.

**TDD/verification:** red tests for the three examples first (fixture transcripts under
`tests/fixtures/`); full `python3 tests/test_agent_team_closeout.py` green; run
`tests/test_closeout_hook.sh` too.

**Discretion:** transcript-parsing implementation details; fixture layout; how the allow is
logged.

**Escalation:** Stop payloads do not carry `transcript_path` (then and only then fall back
to dispatch/subagent-stop event counters with a floor at 0, and record the leak risk in
the report); JSONL pairing cannot be established reliably.

**Commit intent:** `feat(closeout): stop hook is in-flight-dispatch aware — no receipt demands while waiting` — paths: hook, tests, `agents/orchestrator.md` (vocabulary line).

## T6-serialize-mutating-dispatches

**Outcome:** the closeout hook's `dispatch` mode blocks starting a second concurrent
dispatch to `{builder, executor, deployer}` while one of those is unresolved, unless the
new dispatch's prompt carries `PARALLEL_SAFE: no git mutation in this dispatch`.

**Acceptance mapping:** incident root cause — the orchestrator's own committer raced its
builder in one checkout, landing the plan doc on the wrong branch (fact 7); the duplicate
committer dispatch → evidence: tests below.

**Files:** Modify: `hooks/agent_team_closeout.py` (`_initialize`/dispatch path, reusing
T5's `_inflight_dispatches` extended to return unresolved dispatch types). Test:
`tests/test_agent_team_closeout.py`. Modify: `agents/orchestrator.md` (rule + marker doc:
"git-mutating dispatches are serialized per checkout; the forgotten-override default is
blocked, not parallel").

**Interfaces/invariants:** serialized set is exactly `{builder, executor, deployer}`
(git-mutating in practice; `MUTATING_ROLES` at line 18 serves the baseline-capture logic —
do not repurpose it, define `GIT_SERIALIZED_ROLES`). The marker is an exact literal line.
Block message must name the unresolved dispatch type it is waiting on.

**Executable examples:** Given an unresolved builder dispatch — When an executor dispatch
starts without the marker — Then exit 2 with "serialize git-mutating dispatches: builder
still in flight". Given the same state — When the executor prompt contains the exact marker
— Then allow. Given no unresolved serialized dispatch — Then allow.

**Preflight:** confirm PreToolUse(Agent) payload includes `transcript_path` and
`tool_input.prompt` (fixtures or a live payload capture).

**TDD/verification:** red tests for the three examples; full closeout suite green.

**Discretion:** message wording; where the marker constant lives.

**Escalation:** PreToolUse payload lacks the transcript path or prompt (report; do not ship
a counter-based approximation without recording the leak risk).

**Commit intent:** `feat(closeout): serialize git-mutating dispatches per checkout` — paths:
hook, tests, orchestrator.md.

## T7-truthful-baseline-attribution

**Outcome:** the hook never claims ownership it cannot know: the uncommitted-changes block
message says "changed since the session baseline (this hook cannot attribute which process
wrote them)"; restore guidance is emitted only for paths that were dirty AT baseline
(true baseline dirt), never for files created during the session; `agents/orchestrator.md`
forbids inferring file ownership from hook wording (the line-3627 error).

**Acceptance mapping:** incident findings — "Task-owned" mislabel, the unattributable
screenshot committed on the hook's say-so, restore-blob confusion → evidence: tests below +
a drift-style grep test that the string "Task-owned" no longer appears in hook output.

**Files:** Modify: `hooks/agent_team_closeout.py` (`_stop` block message; restore logic if
adopted in T4). Test: `tests/test_agent_team_closeout.py`. Modify: `agents/orchestrator.md`.

**Interfaces/invariants:** paths in `baseline_dirty` → eligible for restore guidance; paths
absent at baseline → listed as "created during this session — verify origin before
committing". The commit-the-delta instruction survives; only the false attribution goes.

**Executable examples:** Given baseline_dirty contains README.md and the current tree adds
newfile.png — When Stop fires — Then the message lists newfile.png under created-this-
session wording and does not call it task-owned. Given README.md's content changed from its
baseline signature — Then restore guidance may reference README.md only.

**Preflight:** read the T4-reconciled restore logic as it now stands in the repo file.

**TDD/verification:** red tests for both examples; closeout suite green;
`grep -c "Task-owned" hooks/agent_team_closeout.py` returns 0.

**Discretion:** exact message phrasing within the stated semantics.

**Escalation:** none specific — this task is self-contained.

**Commit intent:** `fix(closeout): stop asserting per-session ownership the hook cannot know` — paths: hook, tests, orchestrator.md.

## T8-linter-self-describing-blocks

**Outcome:** every BLOCK from `tools/lint_completion_claims.py` appends one exact fill-in
template: the `## Delivery receipt` heading, `- delivery-target:` with its three allowed
values, `- shipment-verdict:` with its two values, and one `- <field>: <status> — <evidence>`
line per LEDGER_FIELDS entry with the five allowed status tokens listed once.

**Acceptance mapping:** incident finding — four blind format retries before anyone read the
linter → evidence: `tests/test_completion_lint.sh` case asserting the template text appears
in BLOCK output.

**Files:** Modify: `tools/lint_completion_claims.py`. Test: `tests/test_completion_lint.sh`.

**Interfaces/invariants:** template appears once per run (not per finding); existing check
messages and exit codes unchanged; PASS output unchanged.

**Executable example:** Given a report missing the receipt heading — When linted — Then
output contains the current BLOCK line plus a section starting `Expected receipt format:`
showing `- verification: <pass|fail|pending|unchecked|not applicable> — <evidence>`.

**Preflight:** read the linter's output-assembly path; read one existing failing case in
`tests/test_completion_lint.sh` to match harness conventions.

**TDD/verification:** red test first; `bash tests/test_completion_lint.sh` green;
`bash tests/test_completion_contract.sh` green.

**Discretion:** template layout/wording, provided every allowed token is shown literally.

**Escalation:** none specific.

**Commit intent:** `feat(lint): self-describing BLOCK output with exact receipt template` — paths: linter, its test.

## T9-derived-gaps-and-cost-report

**Outcome:** a receipt cannot claim `gaps: none` while its own ledger disagrees, and a
SHIPPABLE receipt requires a cost-report field: (a) new lint check — if any LEDGER_FIELDS
value is `fail`, `pending`, or `unchecked`, a `gaps: none` line in the same report is a
BLOCK ("gaps must be derived from the ledger"); (b) `- cost-report:` becomes a required
receipt field when shipment-verdict is SHIPPABLE, status tokens as usual, with evidence
naming the session cost file or its computed totals.

**Acceptance mapping:** incident findings — 62 rote `gaps: none` while real gaps existed;
cost report skipped until demanded → evidence: lint test cases below.

**Files:** Modify: `tools/lint_completion_claims.py` (LEDGER_FIELDS stays 8; cost-report is
verdict-conditional, not a ledger field). Test: `tests/test_completion_lint.sh`. Modify:
`agents/orchestrator.md` closeout section (state the derivation rule and the cost-report
source: the cost file from fact 5, whose path the orchestrator resolves itself — never
delegated to a scribe without the resolved path in the dispatch prompt).

**Interfaces/invariants:** NOT SHIPPABLE receipts do not require cost-report (progress
receipts stay cheap — T5 already removes most of them); `gaps:` lines other than `none`
are not judged by the linter (truth stays the verifier's job, per the linter's stated
philosophy).

**Executable examples:** Given `- verification: pending …` and `gaps: none` in one report —
Then BLOCK naming both lines. Given verdict SHIPPABLE and no `- cost-report:` — Then BLOCK.
Given verdict NOT SHIPPABLE and no cost-report — Then no new BLOCK.

**Preflight:** confirm how the linter scopes "the same report" (receipt_entries) so the
gaps cross-check reads the right region.

**TDD/verification:** three red cases; both lint test suites green.

**Discretion:** message wording; where the conditional-field logic sits.

**Escalation:** none specific.

**Commit intent:** `feat(lint): derive gaps from the ledger; require cost-report at SHIPPABLE` — paths: linter, tests, orchestrator.md.

## T10-critic-tier-cap

**Outcome:** the spec-critic model rule no longer auto-escalates upward: critic = a
DIFFERENT model at the SAME tier as the architect when one exists, else one tier WEAKER;
`fable` is never chosen by rule — any fable dispatch (critic or otherwise) requires a
one-line stated reason in the triage/progress text before dispatch. The model table's
architect/reviewer fable rows gain "requires stated reason" wording.

**Acceptance mapping:** incident finding — mechanical "one tier stronger" put Fable on two
bug-fix critiques ($11.18), against the stated model policy ("forgotten override lands on
the cheap side") → evidence: the rule text at `agents/orchestrator.md:355` and table rows
~170–174 changed; drift test still green.

**Files:** Modify: `agents/orchestrator.md` (line 355 rule, table rows, the Large-tier
"consider fable" line 67 gains the stated-reason requirement). Test:
`tests/test_decision_discipline_drift.sh` (update its expected text if it pins the old rule).

**Interfaces/invariants:** independence requirement (different model) survives; the
degraded-independence flag rule survives unchanged; opus remains the ceiling absent a
stated reason.

**Executable example:** architect ran opus → critic runs sonnet or haiku (different model,
same-or-weaker tier), never fable; architect ran sonnet → critic runs opus is NO longer the
default — critic runs haiku or a different sonnet-tier model; escalation to opus permitted
only with the stated-reason line.

**Preflight:** `grep -n "one tier stronger" agents/orchestrator.md`; run the drift test to
see what text it pins before editing.

**TDD/verification:** `bash tests/test_decision_discipline_drift.sh` green;
`bash tests/test_agent_frontmatter.sh` green (model pins untouched).

**Discretion:** exact prose, provided the three fixed rules (different model, no upward
auto-escalation, fable-requires-stated-reason) are unambiguous.

**Escalation:** the drift test pins the old rule in other agent files too (then update all
pinned copies in this task — list them in the report).

**Commit intent:** `fix(orchestrator): critic model rule — same tier, never auto-fable` — paths: orchestrator.md (+ any drift-pinned agent files), drift test.

## T11-researcher-routing-guard

**Outcome:** the dispatch guard blocks researcher dispatches whose prompt asks for
present-state shell verification, with an override marker for genuine research:
prompts matching (case-insensitive) any of `git `, `rev-parse`, `merge-base`, `run the`,
`execute`, `parse the.*transcript`, `\.jsonl` are blocked with "researcher has no shell —
route present-state verification to the executor, or include `RESEARCH_ONLY: sources
provided in prompt` if this is document analysis of provided material."

**Acceptance mapping:** incident finding — two wasted researcher dispatches (git ancestry
"from memory"; JSONL parsing) → evidence: guard test cases below.

**Files:** Modify: `hooks/agent-team-dispatch-guard.sh`. Test: `tests/test_dispatch_guard.sh`.
Modify: `agents/orchestrator.md` routing note: "present-state facts (git, files, processes,
transcripts) → executor; the researcher analyzes sources, it cannot observe the machine."

**Interfaces/invariants:** guard stays fail-closed on parse errors (existing pattern);
applies only to `subagent_type` researcher; the marker is an exact literal; all existing
guard behavior unchanged.

**Executable examples:** researcher + "verify 8332d6a8 is on origin/main with git
merge-base" → exit 2. researcher + same prompt + the RESEARCH_ONLY line → exit 0.
executor + any prompt → exit 0 (unchanged).

**Preflight:** read the guard's existing prompt access (`.tool_input.prompt`) and test
harness conventions in `tests/test_dispatch_guard.sh`.

**TDD/verification:** three red cases; `bash tests/test_dispatch_guard.sh` green.

**Discretion:** regex assembly details; adding at most two more verb patterns if tests
show gaps.

**Escalation:** prompt not present in PreToolUse payload.

**Commit intent:** `feat(guard): block shell-verb prompts routed to the shell-less researcher` — paths: guard, its test, orchestrator.md.

## T12-dispatch-budget-ratchet

**Outcome:** unbounded dispatch fan-out gets a visible stop-loss: every time a session's
cumulative Agent-dispatch count crosses a multiple of the configured checkpoint (default
10; config key `dispatch_checkpoint` in a new `hooks/agent-team-budgets.json`), the guard
blocks ONCE, requiring the next dispatch attempt's prompt to carry
`WORKFORCE_BUDGET_ACK: <count> dispatches — continuing because <reason>`; the ack line's
presence allows that and subsequent dispatches until the next threshold.

**Acceptance mapping:** incident finding — 47 dispatches with no re-triage checkpoint; the
$51 surprise → evidence: guard tests below. (In the incident session this fires at 10, 20,
30, 40 — four forced, human-visible acknowledgments.)

**Files:** Create: `hooks/agent-team-budgets.json` (`{"schema":1,"dispatch_checkpoint":10}`).
Modify: `hooks/agent-team-dispatch-guard.sh` (count via T5's ground truth: unresolved +
resolved Agent tool_use blocks in the transcript — a jq scan of `transcript_path`; no
mutable counter file). Test: `tests/test_dispatch_guard.sh`. Modify: `agents/orchestrator.md`
(document the ack line; the reason must state tier and why continuing is proportionate).

**Interfaces/invariants:** missing/invalid config → checkpoint 10 (fail to the strict
side); count includes all Agent dispatches regardless of type; the ack must appear in the
blocked-then-retried dispatch's own prompt (the guard is stateless across calls — the
threshold test is `count >= N*k` and `prompt lacks ack for tier N*k`).

**Executable examples:** 9 prior dispatches → 10th attempt without ack → exit 2 with the
required ack format in the message. Same attempt with `WORKFORCE_BUDGET_ACK: 10 dispatches
— continuing because standard-tier route mid-build` → exit 0. 11th–19th without ack →
exit 0.

**Preflight:** confirm the guard receives `transcript_path`; measure jq scan wall time on
a large transcript (must stay well under hook timeout — record the number).

**TDD/verification:** three red cases with fixture transcripts; guard suite green.

**Discretion:** jq implementation; message wording; fixture shape.

**Escalation:** transcript unavailable to PreToolUse (report and reduce scope to a
documented orchestrator.md checkpoint rule — do not ship a counter file silently).

**Commit intent:** `feat(guard): dispatch-count budget ratchet with explicit acknowledgment` — paths: guard, budgets config, tests, orchestrator.md.

## T13-deploy-ops-verifier-contracts

**Outcome:** three agent contracts close the incident's verification/rollback gaps:
(a) `agents/ops.md` + `agents/deployer.md`: any production DATA mutation (object overwrite,
snapshot rebuild) must capture pre-mutation rollback identifiers (e.g., S3 version IDs)
BEFORE mutating and record them where the deploy runbook lives; (b) `agents/deployer.md`:
post-deploy smoke must include the page's default entry request (no parameters,
unauthenticated) asserting status class, with the explicit rule "401 proves liveness and
auth-gating only — it is never acceptance evidence"; (c) `agents/verifier.md`: a visual
acceptance criterion requires a full-page screenshot at a production-representative
viewport, and a page-facing change's ACs must include the user's landing path (default
request, then the primary click-through), not only the changed element.

**Acceptance mapping:** incident findings — snapshots overwritten with no captured version
IDs; every automated check green while the first human login 404'd; AC-7 "passed" while the
real layout was broken → evidence: the three contract texts contain the rules; frontmatter
test green.

**Files:** Modify: `agents/ops.md`, `agents/deployer.md`, `agents/verifier.md`.

**Interfaces/invariants:** rules are stated as MUST-level contract lines in each agent's
own voice/format (match surrounding prose density); no model pins change.

**Executable example (contract semantics):** Given a task rebuilding prod S3 snapshots —
Then the ops dispatch is non-compliant unless its report lists per-object pre-mutation
version IDs. Given a deployed page change — Then deployer smoke includes
`curl -s -o /dev/null -w '%{http_code}' <entry-URL-default-request>` and classifies
401=alive/gated, 404/5xx=broken.

**Preflight:** read each agent file's existing verification/rollback sections to anchor
placement; run `bash tests/test_agent_frontmatter.sh` baseline.

**TDD/verification:** frontmatter test green; a grep check per rule keyword in the report.

**Discretion:** wording and placement.

**Escalation:** none specific.

**Commit intent:** `feat(agents): rollback identifiers for data mutations; entry-path smoke; full-page visual acceptance` — paths: the three agent files.

## T14-install-freshness-check

**Outcome:** a stale or drifted install announces itself: in snapshot mode the orchestrator's
session-start build line (orchestrator.md line ~42 flow) is extended — after reading the
manifest, if the manifest's `repo` path is readable, compare `manifest.commit` to
`git -C <repo> rev-parse HEAD` (via the session's own Read/Bash, one command); on mismatch
the build line gains: `— BEHIND framework HEAD <short-sha>; run bash install.sh` (and the
orchestrator treats running with a stale build as a disclosed degradation, not a silent
fact). Additionally `install.sh --check` guidance: the orchestrator recommends it whenever
drift is suspected.

**Acceptance mapping:** incident finding — the session ran build 6ea4b3f while the pricing
fix 75c306d sat on framework HEAD the whole time; plus fact 2's silent drift → evidence:
orchestrator.md text; manual walkthrough in a consumer project after T17's install.

**Files:** Modify: `agents/orchestrator.md` (session-start section, line ~42 region).

**Interfaces/invariants:** manifest already carries `commit` and `repo` keys (verified).
The check is read-only and must not block startup — it changes the banner text only.
Live-plugin mode is exempt (it runs the checkout directly).

**Executable example:** manifest commit 6ea4b3f, repo HEAD 75c306d → banner:
`team build 6ea4b3f, installed 2026-07-16 — BEHIND framework HEAD 75c306d; run bash install.sh`.

**Preflight:** confirm manifest keys (`jq keys ~/.claude/agent-team-manifest.json`);
confirm the orchestrator has Bash in snapshot mode (it does not — it has Read/Glob/Grep
only; so specify the comparison as: Read the manifest, then Read
`<repo>/.git/HEAD`/`refs` via the Read tool, or dispatch nothing — resolve which mechanism
works with the orchestrator's actual tool list and record it).

**TDD/verification:** no automated seam; verification is the T17 walkthrough plus
orchestrator.md text review.

**Discretion:** the exact read mechanism per the preflight finding.

**Escalation:** neither Read-based mechanism can resolve HEAD (report; fall back to
recommending `install.sh --check` in the banner unconditionally when the install is >7
days old by manifest date).

**Commit intent:** `feat(orchestrator): session banner discloses installs behind framework HEAD` — path: orchestrator.md.

## T15-worktree-hygiene-report

**Outcome:** a read-only hygiene report replaces both silent bloat and dangerous auto-GC:
new `tools/worktree-hygiene.sh <repo>` lists each registered worktree with evidence —
branch, merged-into-main (yes/no), tree clean (yes/no), last commit age — and a final line
counting removal candidates (merged AND clean AND not current). It never deletes.
`agents/orchestrator.md` session-start: run it (via executor on Trivial rules) when the
repo has ≥3 registered worktrees, and surface candidates to the human with the exact
`git worktree remove` commands; an environment-breaking artifact (the E2BIG case) is
always in scope to REPORT, regardless of who created it.

**Acceptance mapping:** incident findings — E2BIG from 433 deny-paths; closeout policy
"not this task's to remove" leaving the breaker in place → evidence: script test below;
orchestrator.md text.

**Files:** Create: `tools/worktree-hygiene.sh`. Test: new `tests/test_worktree_hygiene.sh`
(fixture repo with one merged-clean and one diverged worktree). Modify:
`agents/orchestrator.md`.

**Interfaces/invariants:** read-only (no git mutation of any kind — enforce by not
including a delete path at all); output stable one-line-per-worktree TSV-ish format;
exit 0 always.

**Executable example:** Given a repo with worktree A (branch merged, clean) and worktree B
(unique commits) — When the script runs — Then A is listed `candidate` with its removal
command shown, B listed `keep: unique commits`, and the summary reads `1 removal candidate`.

**Preflight:** review `tests/test_dispatch_guard.sh` harness style for fixture-repo
construction patterns already used in this suite.

**TDD/verification:** red test with the fixture; `bash tests/test_worktree_hygiene.sh`
green; `shellcheck` clean if shellcheck is present (record if absent).

**Discretion:** output formatting; age computation.

**Escalation:** none specific.

**Commit intent:** `feat(tools): read-only worktree hygiene report` — paths: script, test, orchestrator.md.

## T16-telemetry-from-cost-file

**Outcome:** dispatch telemetry is derived, not hand-authored: the closeout telemetry
contract (in `agents/orchestrator.md` and `agents/scribe.md`) requires the telemetry CSV to
be generated from the session cost file's `dispatches` map — one row per dispatch, exact
tokens and cost, `cost_available` true/false from the file's status — and the orchestrator
MUST resolve and pass the cost-file path (fact 5's naming scheme) in the scribe's dispatch
prompt. A scribe telemetry dispatch without a resolved path in its prompt is non-compliant.
The receipt's cost-report field (T9) cites the same file. Free-typed "cost file
unavailable" without a read of the resolved path is named as a forbidden move.

**Acceptance mapping:** incident findings — 6 hand-written null rows vs ~45 dispatches; the
orchestrator laundering the scribe's path-blindness into "cost file unavailable" →
evidence: both contract texts; consistency with the cost file schema verified against a
real file.

**Files:** Modify: `agents/orchestrator.md` (closeout/telemetry section), `agents/scribe.md`.
Read-only reference: `hooks/agent-team-cost.sh` (schema), `docs/telemetry/README.md`
(candidate — confirm it exists; align its schema text if present).

**Interfaces/invariants:** telemetry schema columns stay as deployed (fact 9 header); the
orchestrator's own-session usage is explicitly out of telemetry scope and the cost-report
must SAY so (subagent totals + "orchestrator usage additional, see /usage") — the $51
lesson that the subtotal is not the total.

**Executable example:** Given a session cost file with 45 dispatch entries — Then a
compliant telemetry CSV has 45 rows and its summed cost equals the file's rollup total.

**Preflight:** read one real cost file under `~/.claude/logs/agent-team-cost/` to confirm
the `dispatches` map fields available per entry; check whether `docs/telemetry/README.md`
exists in this repo.

**TDD/verification:** contract-text review; schema cross-check recorded in the report.

**Discretion:** wording; whether a small jq one-liner example is embedded in scribe.md.

**Escalation:** the cost file's per-dispatch entries lack a field the CSV schema needs
(report the gap; do not invent a derivation).

**Commit intent:** `feat(telemetry): derive dispatch telemetry from the session cost file` — paths: orchestrator.md, scribe.md (+ telemetry README if present).

## T17-integrate-and-reinstall

**Outcome:** all of this plan's commits are merged to `ai-agent-team` main and installed:
`bash install.sh` run once, `bash install.sh --check` clean (fact 2's drift gone), the full
test suite green on main, and the session banner in a fresh consumer-project session shows
the new build with no BEHIND warning.

**Acceptance mapping:** incident finding #stale-build + fact 2 → evidence: `--check` output,
test-suite output, banner observation.

**Files:** none new — integration and installation.

**Interfaces/invariants:** merge the plan worktree branch via the repo's normal flow
(jayheavner account); do NOT install from the worktree — install from main after merge.
Full suite = every `tests/test_*.sh` plus `python3 tests/test_agent_team_closeout.py`.

**Preflight:** `gh auth status` (jayheavner active); worktree branch rebased/merges clean
onto main; full suite green in the worktree first.

**TDD/verification:** suite output attached; `--check` output attached; one fresh session
banner observed (may be done by Jay).

**Discretion:** merge mechanism (PR vs local merge) per repo convention.

**Escalation:** `--check` still reports divergence after install (names files this plan
missed — stop and report them); any test red on main that was green in the worktree.

**Commit intent:** merge commit only.

---

## Self-review (completed at authoring)

- Coverage: all merged findings map to tasks — receipt spam/races/markers/churn (T5),
  format guessing (T8), gaps/cost-report (T9, T16), tiering (T10), routing (T11),
  budgets/stop-loss (T12), ceremony (T12 + existing Trivial tier, per B's finding that the
  lane exists and needs mechanical teeth, which T12 provides), shared-checkout corruption
  (T6, T7 — with the corrected self-race diagnosis), rollback/entry-path/visual
  verification (T13), stale install + never-committed drift (T4, T14, T17), E2BIG (T15),
  telemetry/accounting (T16). Remediating the innovation-awards project itself (its
  stranded doc, stale worktree, telemetry CSV) is OUT OF SCOPE: this plan improves the
  orchestration only — the orchestration deals with other projects. Deliberately excluded: B's full "lifecycle state machine" rewrite —
  T5+T6 deliver its enforcement value inside the existing hook without a new subsystem
  (YAGNI); revisit only if the transcript-scan mechanism fails preflight.
- Placeholders: none; every candidate path is labeled and has a preflight step.
- Consistency: marker literals (`WORKFORCE_WAITING`, `PARALLEL_SAFE`, `WORKFORCE_BUDGET_ACK`,
  `RESEARCH_ONLY`) each defined once and reused verbatim.
- Feasibility: every named file verified present at HEAD (facts 1–10) except explicitly
  marked candidates (telemetry README, cost-file exact name, transcript payload fields).
- Observability: each task names evidence a verifier can reproduce without trusting the
  builder.
