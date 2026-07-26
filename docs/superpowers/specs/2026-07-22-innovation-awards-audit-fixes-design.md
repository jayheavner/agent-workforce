# Innovation-awards audit fixes — design

Source: 2026-07-22 audit of the innovation-awards work-machine session (workforce
build 187007b). Every problem statement below was verified against this repo's
code, real session transcripts, and real cost files on 2026-07-22; each fix names
its evidence. Two audit findings (stale-read block loop, telemetry in client
repos) are already fixed on main and are NOT re-designed here.

Five deliverables, in implementation order (smallest verified fix first):

1. Closeout cap re-arm (one line + test)
2. Background-dispatch attribution (cost_report.py)
3. Cost-table freshness check (closeout hook)
4. Status-note destination by integration mode (closeout skill + policy)
5. gh push-preflight recipe + work-machine runbook

---

## 1. Closeout enforcement cap re-arms after a written-off closeout

**Problem (verified in `hooks/agent_team_closeout.py`).** The cap branch
(`blocks >= MAX_BLOCKS`) allows the stop but saves no state: `blocks` stays at
the cap and `acked_total` is never advanced. Every later stop in the session —
including closeouts for entirely new dispatched work — fails open immediately.
In the incident, the whole push/PR/merge phase ran with zero closeout
enforcement and its cost was never reported.

**Design.** In the cap branch, before `allow()`:

```python
save_state(session_id, {"acked_total": total, "blocks": 0})
```

Semantics change: MAX_BLOCKS bounds blocks **per closeout**, not per session.
The capped closeout is written off (its dispatches count as acked, exactly as a
passing stop would record), and the next new dispatch re-arms enforcement with
a fresh block budget. The stderr warning stays. Wedge-protection is unchanged:
any single closeout still fails open after 3 blocks.

**Tests (red first, `tests/test_agent_team_closeout.py`).** One session, two
closeouts: burn 3 blocks on closeout #1 → capped stop allows; append a new
dispatch + stop with no cost report → must block again (today it fails open).

---

## 2. Background dispatches get real names in cost reports and telemetry

**Problem (verified).** 14 of 16 agents in the incident's per-agent table were
"unknown". Mechanism, confirmed on this machine's own session data
(session 481c7138: all 4 async-launched dispatches → "unknown" in the cost
file; all 7 sync → correctly named):

- `hooks/agent-team-cost.sh` records `agent_type` only when the parsed file's
  id equals the firing dispatch's `tool_response.agentId`.
- Background dispatches complete via task-notification — no PostToolUse fire —
  and their **launch stub carries `agentId` but no `agentType`** (verified on
  real records: `{'agentId': …, 'status': 'async_launched'}`). The bash hook
  can never name them, regardless of fire timing.

**Design.** Fix in `hooks/cost_report.py` only; `agent-team-cost.sh` stays
untouched (its `agent_type` field becomes advisory — note this in both files'
header comments). The main transcript already contains everything needed, and
the join was verified to recover **11/11 dispatch types** including all async
ones:

- New `agent_types_from_transcript(transcript)`: one pass over the main
  transcript. Collect `tool_use.id → input.subagent_type` from assistant
  records where `name == "Agent"` (normalize plugin prefixes with
  `.split(":")[-1]`, same as the closeout hook's scan). Collect
  `tool_use_id → agentId` from user records whose sibling `toolUseResult`
  dict carries `agentId`. Join on tool_use id → `{agentId: subagent_type}`.
- Merge precedence in `main()`: transcript map is the base; overlay cost-file
  values only when not `"unknown"` (for sync dispatches they agree anyway).
- This single map already feeds the per-agent table, `proportionality_flags`
  (which currently degrades to the label "subagent"), and the telemetry
  `role` field — one fix, three consumers.

**Tests (red first, `tests/test_cost_report.sh` fixtures).** Fixture main
transcript containing one sync dispatch (result carries `agentType`) and one
async dispatch (stub result, `agentId` only, completion via task-notification
text): per-agent table must name both; telemetry record's `role` must be the
real type for the async one; proportionality flag output must print the role,
not "subagent".

---

## 3. Closeout accepts only a fresh cost table

**Problem (verified).** The hook's only cost check is
`COST_MARKER not in tail` — marker presence. A stale table passes. In the
incident the final post-merge message shipped the pre-merge table
(`$32.76`, missing the entire merge phase) plus a false promise that "the Stop
hook will append the final computed total" — the hook appends nothing, and
nothing challenged the stale number.

**Design.** When the marker IS present, verify freshness by total:

- Parse the claimed grand total from the tail with a regex anchored on the
  exact row `markdown_report` emits (verified format):
  `\|\s*\*\*Total\*\*\s*\|.*\*\*\$([\d,]+\.\d{2})\*\*\s*\|`. Use the LAST
  match in the tail (a message may quote older tables).
- Compute the fresh report (the hook already knows how; `markdown_report`
  emits the same Total row — regex the fresh output the same way).
- Accept when `abs(claimed - fresh) <= max(COST_SLACK_USD, fresh * COST_SLACK_FRACTION)`
  with module constants `COST_SLACK_USD = 1.00`, `COST_SLACK_FRACTION = 0.02`.
  The slack absorbs the orchestrator's own final-turn tokens (observed drift
  per closeout retry in the incident: $0.10–$0.22); a missing merge phase
  (>$3 there) blows through it.
- **Fail open** when either total cannot be parsed (unpriced/partial sessions
  emit no Total row) — the hook never demands facts it cannot verify.
- On mismatch, block with the existing demand text plus one line naming the
  stale total found vs the fresh one. Freshness blocks spend normal blocks;
  the stale-read guard already prevents these from looping on flush races.

Cost: one extra `cost_report.py` subprocess per *passing* closeout stop
(bounded by the existing 60s timeout; today it already runs on every blocking
stop).

**Tests (red first).** (a) tail with correct marker but stale total beyond
slack → block names both totals; (b) stale-but-within-slack → allow;
(c) marker present, no parseable Total row → allow; (d) fresh table → allow.

---

## 4. Status note follows the integration mode

**Problem (verified).** Three rules collide on PR-protected/multi-worktree
tasks: the hook's ledger check requires any claimed `docs/STATUS-*.md` to
exist in cwd; `skills/closeout/SKILL.md` §3 commits the note with the task
delta; a PR-protected main can't take that commit and a multi-worktree task
has no single delta checkout. Incident result: note stranded uncommitted in
the main checkout (feeding dirty-tree noise) and left describing a pre-merge
state after the merge. The work order had even said "no status docs beyond
commits and PR descriptions" — the skill demanded a file anyway.

**Design.** Policy/skill change only; no hook change (ledger check #3 fires
only on *claimed* paths, so a session that writes no file trips nothing).
`skills/closeout/SKILL.md` §3 (Record) becomes mode-aware, resolved by the
already-resolved `policy:closeout-integration` value:

- `commit` / `push` — unchanged: `docs/STATUS-<slug>.md`, committed with the
  delta.
- `pr` / `pr-merge` — the durable record is the PR description(s): outcome,
  evidence, deviations, disclosed decisions. No status file is written to the
  checkout. (The PR body already carries per-item verification evidence under
  the existing conventions; this makes it the single record instead of a
  duplicate.)
- An explicit human opt-out of status artifacts always wins over both.
- New one-line staleness rule in §3: **a record this session makes wrong, this
  session fixes** — any status artifact whose claims a later phase invalidates
  is updated before the final report, not surfaced as a question.

Files: `skills/closeout/SKILL.md` (§2 wording "status notes" → "status
artifacts per integration mode", §3 rewrite), `policy/KEYS.md`
closeout-integration entry gains one sentence noting the key also selects the
status-record destination. Skill edits go through `writing-skills` (eval
scaffolding first) — the eval scenario is the incident: pr-merge task, work
order opting out of status docs, assert no `docs/STATUS-*.md` is created and
the PR bodies carry the record.

---

## 5. gh push preflight — recipe + work-machine runbook

**Problem (verified).** The push batch died on GitHub refusing a branch that
adds `.github/workflows/ci.yml` because the token lacked the `workflow` OAuth
scope. Cost: one dead executor dispatch, an extra question round-trip, a human
browser-auth interruption mid-merge. No recipe covers scopes; `GIT-SSH.md` has
zero scope coverage; `gh auth status` prints token scopes.

**Design — `recipes/GH-PUSH-SCOPES.md`** (recipes/README format; "delivers: gh
can push what the outgoing commits need"):

- **When:** before the first push of any branch; mandatory when outgoing
  commits touch `.github/workflows/**`.
- **Phase 1 (agent):** identity — active `gh` account matches the repo's
  canonical account (cross-link GIT-SSH.md).
- **Phase 2 (agent):** scope inventory — `gh auth status` → parse the token
  scopes line. Required: `repo` always; `workflow` iff
  `git diff --name-only <base>...HEAD -- .github/workflows/` is non-empty.
- **Phase 3 (human-work tagged):** if a scope is missing, agent runs
  `gh auth refresh -h github.com -s workflow`; the browser/device approval is
  the human's (classifier and OAuth both require it).
- **Phase 4 (agent, verify):** re-run `gh auth status`, confirm the scope is
  listed; then push.
- One pointer line added to `GIT-SSH.md`.

**Runbook — `INNOVATION-AWARDS-CLEANUP.md`** (repo root, EA-REPO-CLEANUP.md
pattern; audience: a session on Jay's work machine):

1. `git pull` in the workforce checkout there (build 187007b → current; picks
   up the stale-read and telemetry fixes; the launcher self-updates after
   this one manual pull).
2. In the innovation-awards repo: delete stray
   `docs/telemetry/-Users-*.jsonl`; update or delete the stale
   `docs/STATUS-audit-fix-four-tracks.md` (branches merged 2026-07-22,
   PRs #43–#47).
3. Recompute the true session cost:
   `bin/agent-workforce-cost-report --transcript <that session's transcript>`
   — the reported $32.76 excludes the merge phase.
4. Read the Track C and Track D builder transcripts' final records
   (`agent-*.jsonl` under the session's subagents dir) and report why both
   halted mid-work (~170+ tool calls; cause still unverified — CORRECTION
   2026-07-26: a workforce cap DOES exist, `maxTurns: 150` in
   `agents/builder.md`, present in the audited build 187007b, and is the
   leading hypothesis; the earlier "no workforce cap exists" claim here was
   wrong). Only after that, decide whether dispatch-sizing guidance or a cap
   change is warranted; the interrupted-dispatch guard (2026-07-26
   checks-balances spec §3) already makes any such death detected and
   resumable regardless of cause.
5. Read the machine-local `status-enforcer` and `landing-claim-verifier` hook
   sources; determine whether they read the transcript (same Stop-time flush
   race the closeout hook had) or the message payload; fix or retire. After
   step 2, any further landing-claim fire is signal, not noise.

---

## Out of scope

- Track C/D halt mitigation (cause unverified until runbook step 4 runs).
- Any change to machine-local hooks (not in this repo).
- agent-team-cost.sh rework (attribution moves to cost_report.py by design).
