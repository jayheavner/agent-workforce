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

## T7-truthful-baseline-attribution

**Preflight:** read the T4-reconciled restore logic — T4 rejected the
blob/restore-hint mechanism entirely, so there was no restore logic to build
on; this task starts from the plain baseline-diff message at (pre-edit) line
378.

**Implementation:** the uncommitted-changes block message in `_stop` no
longer contains the literal string "Task-owned". Changed paths are split into
`residue` (present in `baseline_dirty`) — labeled "changed since the session
baseline (this hook cannot attribute which process wrote them)" — and
`created` (absent from baseline) — labeled "created during this session —
verify origin before committing". The commit-the-delta instruction is
unchanged; only the false attribution is gone. `agents/orchestrator.md` gains
a rule forbidding inferring file ownership from hook wording.

**Verification:** 2 new red→green tests
(`test_stop_never_attributes_ownership_it_cannot_know`,
`test_stop_labels_new_file_as_created_this_session_not_task_owned`) plus one
pre-existing test's case-sensitive assertion corrected for the new wording.
`python3 tests/test_agent_team_closeout.py` — 26 tests, green.
`bash tests/test_closeout_hook.sh` — 26 tests green, 90% coverage.
`bash tests/test_decision_discipline_drift.sh` — PASS=3 FAIL=0.
`bash tests/test_agent_frontmatter.sh` — passed=31 failed=0.
`grep -c "Task-owned" hooks/agent_team_closeout.py` — 0 (acceptance grep met).

## T8-linter-self-describing-blocks

**Implementation:** `tools/lint_completion_claims.py` gains a `RECEIPT_TEMPLATE`
constant (built from the existing `LEDGER_FIELDS` tuple, so it can never drift
from the real field list) and `main()` prints it once, after all `BLOCK`
lines, whenever any block fired. PASS output and existing check
messages/exit codes are unchanged.

**Note:** this environment's `grep` is aliased to `ugrep`; a literal pattern
beginning with `-` (e.g. `- delivery-target: ...`) requires `-e` or `--`
before it or `ugrep` misparses it as an option. Recorded here since it
affected test-writing, not the linter itself.

**Verification:** 3 new test cases in `tests/test_completion_lint.sh` (template
appears exactly once on a receipt-less BLOCK, appears once even when a receipt
already exists, absent entirely from PASS output). `bash
tests/test_completion_lint.sh` — PASS=10 FAIL=0. `bash
tests/test_completion_contract.sh` — PASS=21 FAIL=0. `bash
tests/test_closeout_audit.sh` — PASS=23 FAIL=0 (downstream linter-output
coupling unaffected).

## T9-derived-gaps-and-cost-report

**Preflight:** "the same report" scope is the whole report's `lines` list (a
new `GAPS_NONE` regex scans every line, not just the `## Delivery receipt`
block's `entries`), matching the orchestrator's actual usage — `gaps:` is
written as its own prose line in closeout summaries, not inside the receipt.

**Implementation:** new C5 check in `tools/lint_completion_claims.py` — if any
`LEDGER_FIELDS` value is `fail`/`pending`/`unchecked` and a `gaps: none` line
appears anywhere in the report, BLOCK naming the contradicting fields.
`LEDGER_FIELDS` stays 8 fields; `cost-report` is verdict-conditional (new C6):
a `SHIPPABLE` receipt with no `cost-report` field BLOCKs; `NOT SHIPPABLE`
receipts are unaffected. `agents/orchestrator.md` gains the derivation rule in
Gap flags and a `cost-report` requirement in Completion closeout, stating the
orchestrator resolves the cost-file path itself before any scribe dispatch —
never delegated blind, and never "cost file unavailable" without reading the
resolved path first.

**Side effects surfaced and fixed:** the pre-existing `shippable.md` fixture
and the `SHIPPABLE` constant embedded in `tests/test_agent_team_closeout.py`
were both legitimately incomplete under the new C6 check (real SHIPPABLE
receipts without cost-report) — both updated to add the field, which is the
intended behavior change working as designed, not a regression.

**Verification:** 2 new fixtures
(`gaps-none-contradicts-ledger.md`, `shippable-missing-cost-report.md`) and 4
new test cases in `tests/test_completion_lint.sh`. Full suite run: `python3
tests/test_agent_team_closeout.py` — 26 green; `bash
tests/test_closeout_hook.sh` — 26 green, 90% coverage; `bash
tests/test_dispatch_guard.sh` — PASS=37 FAIL=0; `bash
tests/test_completion_lint.sh` — PASS=14 FAIL=0; `bash
tests/test_completion_contract.sh` — PASS=21 FAIL=0; `bash
tests/test_closeout_audit.sh` — PASS=23 FAIL=0; `bash
tests/test_decision_discipline_drift.sh` — PASS=3 FAIL=0; `bash
tests/test_agent_frontmatter.sh` — passed=31 failed=0.

## T10-critic-tier-cap

**Preflight:** `grep -n "one tier stronger" agents/orchestrator.md` located the
rule at line 363 (plan estimated ~355; close enough, same rule). Ran
`tests/test_decision_discipline_drift.sh` before editing: it pins an unrelated
`<!-- two-questions:start/end -->` marker block (lines 350–356 in
orchestrator.md, and corresponding blocks in architect.md/reviewer.md) — no
overlap with the critic rule at line 363, confirmed by line-range check.

**Implementation:** rewrote the critic-model rule: different model, same tier
as the architect when a distinct same-tier model exists, else one tier
weaker; never auto-escalates upward regardless of what the architect ran;
`fable` is never chosen by rule for the critic (or any dispatch) — it requires
a one-line stated reason before dispatch. Updated the model table's
architect/reviewer `fable` upshift cells to read `fable (requires stated
reason)`, and the Large-tier "consider fable for the reviewer" line to state
the same requirement. `grep -rn "one tier stronger" agents/*.md` confirmed no
other agent file pins the old rule text — no escalation needed.

**Verification:** no automated seam for this prose-only task per plan design;
`bash tests/test_decision_discipline_drift.sh` — PASS=3 FAIL=0 (unaffected, as
predicted). `bash tests/test_agent_frontmatter.sh` — passed=31 failed=0 (model
pins on agent files themselves untouched). `bash
tests/test_completion_contract.sh` — PASS=21 FAIL=0.

## T11-researcher-routing-guard

**Preflight:** confirmed via the same evidence as T6 that PreToolUse payloads
carry `tool_input.prompt`; read `tests/test_dispatch_guard.sh`'s existing
`agent_json`/`expect_*` conventions (already reused from T6's work).

**Implementation:** `hooks/agent-team-dispatch-guard.sh` gains
`RESEARCHER_SHELL_VERB_PATTERN` (case-insensitive: `git `, `rev-parse`,
`merge-base`, `run the`, `execute`, `parse the.*transcript`, `\.jsonl`) and
`RESEARCH_ONLY_MARKER`. For `subagent_type: researcher`, a prompt matching the
pattern blocks unless it carries the exact marker line; all other roles are
unaffected. Guard stays fail-closed on parse errors (unchanged existing
pattern). `agents/orchestrator.md`'s research/ops routing paragraph states
the rule: present-state facts → executor, the researcher analyzes sources.

**Verification:** 3 new red→green tests in `tests/test_dispatch_guard.sh`
(shell-verb prompt blocks; same prompt + RESEARCH_ONLY marker allows; executor
with the same prompt allows, unchanged). `bash tests/test_dispatch_guard.sh` —
PASS=40 FAIL=0. Drift, frontmatter, and completion-contract suites re-verified
green after the orchestrator.md edit.

## T12-dispatch-budget-ratchet

**Preflight:** confirmed `transcript_path` is present on PreToolUse (same
evidence as T6). Measured jq scan wall time on a 4000-line/2000-dispatch
fixture transcript: ~14ms — well under any hook timeout.

**Implementation:** new `hooks/agent-team-budgets.json`
(`{"schema":1,"dispatch_checkpoint":10}`). The guard counts ALL Agent
`tool_use` blocks in the transcript (same jq shape as T5/T6, resolved or not
— stateless, no counter file); when the incoming dispatch's own number is a
multiple of the checkpoint, it blocks unless its prompt carries
`WORKFORCE_BUDGET_ACK: <that exact number> dispatches — continuing because
<reason>`. Missing/invalid config falls back to checkpoint 10.
`agents/orchestrator.md`'s Rules section documents the ack format and that
the reason must state tier and proportionality. `install.sh` now ships
`agent-team-budgets.json` — added to `HOOK_FILES`, the copy step, the
preexisting-backup capture, the `restore()` case statement, and the
partial-install cleanup, matching every other hook config file's pattern.

**Verification:** 4 new red→green tests in `tests/test_dispatch_guard.sh`
(10th dispatch blocks without ack; 10th with ack allows; 11th without ack
allows; 19th without ack allows — next checkpoint is 20). `bash
tests/test_dispatch_guard.sh` — PASS=44 FAIL=0. `bash
tests/test_install_skills.sh` — PASS=36 FAIL=0. `bash
tests/test_install_retire.sh` — passed=9 failed=0. `bash install.sh --check`
run after these changes: correctly STALE on every file this plan touched so
far (orchestrator.md, agent-team-cost.sh, agent-team-dispatch-guard.sh,
agent_team_closeout.py, lint_completion_claims.py), DRIFT still present on
the hand-edited installed closeout hook (T17's job), no new/unexpected drift
introduced by the new budgets file itself.

## T13-deploy-ops-verifier-contracts

**Preflight:** read each agent file's existing verification/rollback sections
to anchor placement; `bash tests/test_agent_frontmatter.sh` baseline —
passed=31 failed=0 before editing.

**Implementation:** (a) `agents/ops.md` and `agents/deployer.md` each gain a
MUST-level line: any production DATA mutation (object overwrite, snapshot
rebuild — not infrastructure config) requires capturing pre-mutation rollback
identifiers (e.g., S3 version IDs, prior snapshot ARN) before mutating. (b)
`agents/deployer.md`'s smoke-check step always includes the page's default
entry request (no parameters, unauthenticated) with an explicit status-class
rule: 401 proves liveness and auth-gating only, never acceptance evidence;
404/5xx is broken. (c) `agents/verifier.md` gains two rules: a page-facing
change's ACs must include the user's landing path (default request, then
primary click-through), and any visual acceptance criterion requires a
full-page screenshot at a production-representative viewport, not a cropped
capture.

**Verification:** `bash tests/test_agent_frontmatter.sh` — passed=31 failed=0
(unchanged, no frontmatter/model pins touched). Grep checks per rule keyword:
`rollback identifier` in both ops.md and deployer.md (1 each); `401` in
deployer.md (1); `full-page screenshot` and `landing path` in verifier.md (1
each). `bash tests/test_completion_contract.sh` — PASS=21 FAIL=0.

## T14-install-freshness-check

**Preflight:** `jq keys ~/.claude/agent-team-manifest.json` confirmed
`commit` and `repo` keys exist (plus `files`, `installed_at`,
`skills_framework_revision`). Confirmed the orchestrator's snapshot-mode tool
list (line 6) has Read/Glob/Grep only, no Bash — so the mechanism must be
Read-based, not a `git rev-parse` shell command. Resolved the mechanism: Read
`<repo>/.git/HEAD` → branch ref name (e.g. `ref: refs/heads/main`), then Read
`<repo>/.git/refs/heads/<branch>` → the commit SHA directly. Verified this
matches `git -C <repo> rev-parse HEAD` exactly for the common case (checked
out branch, loose ref, no packed-refs) — both returned `75c306d3c5...` for
this repo's main. Both Read-based steps resolved cleanly; no escalation to
the fallback (`install.sh --check` recommendation) was needed.

**Implementation:** `agents/orchestrator.md`'s session-start section (line
42 region) gains the freshness check for snapshot mode only (live plugin mode
runs the checkout directly, so it's exempt): read-only, never blocks startup;
an unreadable ref (packed, detached HEAD) skips the check rather than
guessing. On mismatch, the build line gains `— BEHIND framework HEAD
<short-sha>; run bash install.sh`.

**Verification:** no automated seam per plan design — verification is this
preflight's SHA-match confirmation plus the T17 walkthrough. `bash
tests/test_agent_frontmatter.sh` — passed=31 failed=0. `bash
tests/test_decision_discipline_drift.sh` — PASS=3 FAIL=0. `bash
tests/test_completion_contract.sh` — PASS=21 FAIL=0. No test in the repo pins
the build-line wording text (grepped, none found), so the prose rewrite has
no drift risk.

## T15-worktree-hygiene-report

**Preflight:** reviewed `tests/test_dispatch_guard.sh`'s fixture-construction
style (mktemp-based, self-contained repo setup in `setUp`-equivalent shell)
and reused the same pattern for the new test's fixture repo.

**Implementation:** `tools/worktree-hygiene.sh <repo>` — no delete path
exists anywhere in the script (enforced by omission, per the fixed
invariant). For each `git worktree list --porcelain` entry: computes
merged-into-main (`git merge-base --is-ancestor`), tree-clean
(`git status --porcelain`), and last-commit age in days; classifies as
`candidate` (merged AND clean AND not the current worktree, with its exact
`git worktree remove <path>` command shown), `keep: current worktree`,
`keep: unique commits`, or `keep: dirty tree`. Always exits 0. Base branch
resolution prefers `main`, then `master`, then the current branch (mirrors
the closeout hook's `_base_branch` logic). `agents/orchestrator.md`'s
session-start section now runs it via the executor under the Trivial-tier
rule when 3+ worktrees are registered, surfaces candidates with their exact
removal command, and states that an environment-breaking artifact is always
in scope to report regardless of ownership.

**Note:** `git worktree list --porcelain` reports paths through its own
symlink resolution (`/private/tmp/...` on macOS, not the `/tmp/...` alias) —
the test fixture had to resolve worktree paths the same way (`cd ... && pwd
-P`) to match the script's output; this was a test-authoring correction, not
a script bug (confirmed by inspecting git's own porcelain output directly).

**Verification:** fixture repo with one merged-clean worktree (asserted
`candidate` with its exact removal command) and one diverged worktree
(asserted `keep: unique commits`); a read-only invariant check (repo refs and
worktree list byte-identical before/after the script runs). `bash
tests/test_worktree_hygiene.sh` — PASS=7 FAIL=0. `shellcheck` not present in
this environment — recorded per Discretion; `bash -n` syntax check passed.
Sanity-run against this actual repo (3 registered worktrees) — correct
output, exit 0, 0 candidates (all three are either current or have unique
commits). Drift, frontmatter, and completion-contract suites re-verified
green after the orchestrator.md edit.

## T16-telemetry-from-cost-file

**Preflight:** read a real cost file for this project
(`~/.claude/logs/agent-team-cost/-Users-jay-claude-ai-agent-team--*.json`) —
confirmed the `dispatches` map's per-entry fields (`agent_type`, `file`,
`requests`, `models` keyed by model id with token counts + `cost_usd`,
`web_search_requests`, `web_fetch_requests`) and the top-level `totals`,
`status`, `version`. `docs/telemetry/README.md` exists and already specifies
a v1 schema whose `dispatch_id` "joins to the cost file" — the derivation
intent was already documented; the gap was the orchestrator's path being
optional ("or the path the orchestrator gives you") and no rule forbidding
free-typed unavailability.

**Implementation:** `agents/orchestrator.md`'s Dispatch telemetry section now
states the orchestrator resolves the cost file's exact path itself (same
Glob pattern as the cost report) and MUST put it in the scribe's dispatch
prompt — a telemetry dispatch without the resolved path is non-compliant.
`agents/scribe.md` drops the optional-fallback wording ("default directory...
or the path the orchestrator gives you") in favor of requiring the resolved
path from the prompt, and forbids writing "cost file unavailable" without
having read that path first.

**Schema cross-check:** `jq` over the sampled cost file confirmed every
dispatch used exactly one model (`max` model-key count = 1), consistent with
the README's singular `resolved_model`/`tokens`/`cost_usd` fields — no schema
gap to report per the task's Escalation clause.

**Verification:** contract-text review (no automated seam per plan design).
`bash tests/test_agent_frontmatter.sh` — passed=31 failed=0. `bash
tests/test_decision_discipline_drift.sh` — PASS=3 FAIL=0. `bash
tests/test_completion_contract.sh` — PASS=21 FAIL=0.

## T17-integrate-and-reinstall (blocked — status as of this session)

**Preflight:** `gh auth status` — BOTH `jheavner` and `jayheavner` GitHub
accounts report "Failed to log in... The token in keyring is invalid."
Neither account is currently usable. Per standing instruction, this halts
before any merge/push; no attempt was made to re-authenticate, refresh
tokens, or use an alternate credential path — that decision belongs to the
user.

**Full suite run (every `tests/test_*.sh` plus `python3
tests/test_agent_team_closeout.py`) in this worktree, prior to merge:**

One failure surfaced on the first pass: `tests/test_codex_profiles.sh`
(PASS=14 FAIL=8) — `scripts/render_codex_agents.py --check` reported the
checked-in Codex `.toml` profiles under `codex/agents/` and `codex/profiles/`
as stale. Root cause: T13 and T16 edited `agents/ops.md`, `deployer.md`,
`verifier.md`, and `scribe.md` (source files the generator renders from)
without regenerating the derived profiles. Fixed by running `python3
scripts/render_codex_agents.py` (regenerated 14 files, matching exactly the
four agent files this plan touched) and committing the result
(`chore(codex): regenerate profiles after T13/T16 agent-contract edits`).
Rerun: `codex-profile tests: PASS=22 FAIL=0`.

**Full suite result after the fix — every suite green:**
test_acceptance_lint, test_agent_frontmatter, test_audit_hook,
test_chatgpt_plugin, test_closeout_audit, test_closeout_hook,
test_codex_profiles (22/22 after fix), test_completion_contract,
test_completion_lint, test_cost_hook, test_decision_discipline_drift,
test_dispatch_guard (44/44), test_execution_handoff_text, test_gap_loop_text,
test_install_retire, test_install_skills, test_orchestrator_autonomy,
test_plugin_mode, test_process_assurance_cli, test_process_assurance_hook,
test_process_assurance_integration, test_scoreboard, test_secrets_hook,
test_worktree_hygiene (7/7), and `python3 tests/test_agent_team_closeout.py`
(26/26) — all exit 0.

**Pre-merge `install.sh --check` (this worktree, all commits through the
codex-profile fix):**
```
check: STALE — repo agents/deployer.md changed since the last install; re-run install
check: STALE — repo agents/ops.md changed since the last install; re-run install
check: STALE — repo agents/orchestrator.md changed since the last install; re-run install
check: STALE — repo agents/scribe.md changed since the last install; re-run install
check: STALE — repo agents/verifier.md changed since the last install; re-run install
check: STALE — repo hooks/agent-team-cost.sh changed since the last install; re-run install
check: STALE — repo hooks/agent-team-dispatch-guard.sh changed since the last install; re-run install
check: DRIFT — /Users/jay/.claude/hooks/agent_team_closeout.py differs from the last install (hand-edited under ~/.claude/?)
check: STALE — repo hooks/agent_team_closeout.py changed since the last install; re-run install
check: STALE — repo tools/lint_completion_claims.py changed since the last install; re-run install
check: FAIL — drift detected (lines above). Reconcile any hand edits back into the repo, then re-run 'bash install.sh'
```
Every STALE line names exactly a file this plan modified (T5–T16); expected
pre-install state, not a new problem. The DRIFT line is fact 2's pre-existing
condition. Both clear once `bash install.sh` runs from main.

**gh auth investigation:** `gh auth status` — `jheavner` active but its
keyring token is invalid; `jayheavner` also invalid. `gh auth switch -h
github.com -u jayheavner` fails at the keyring layer itself ("failed to move
active token in keyring: exit status 161") — a macOS Keychain access issue,
not a `gh` config problem correctable from this session. Reported to the
user; no workaround attempted (per standing instruction against trying
alternate credentials on an unexpected error).

**Not yet done (blocked on `gh`/Keychain auth):** merge to main, `bash
install.sh` run from main, post-install `install.sh --check` clean
confirmation, and the fresh consumer-project session banner observation.
These remain T17's open items until the human resolves GitHub/Keychain
authentication.
