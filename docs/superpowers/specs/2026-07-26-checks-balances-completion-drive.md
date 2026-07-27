# Checks-and-balances + completion drive — design

Source: 2026-07-26 session. Two problems, both verified against this repo and
the 2026-07-22 innovation-awards audit
(`docs/analysis/2026-07-22-innovation-awards-workforce-issues.md`):

**Problem A — the builder authors its own success criteria.** On the common
"contained build" route no architect runs, so the only statement of "done" is
the builder's own tests. The verifier's contract is "run the exact
verification command" for criteria *it is given* — and those criteria derive
from the builder's report. Independence of execution, not of criteria. The
audit shows the predicted failure three times: the A3 test that never covered
the gap the reviewer later found (issue 8), frontend "proven" only by the
builder's own vitest assertions (issue 4), and half-built Slack alerting
declared shipped (issue 3). Nothing upstream of the builder defines done;
nothing downstream checks against the original request unless a reviewer
happens to be routed.

**Problem B — silent mid-work death is invisible.** Track C and D builders
halted at 177 and 170 tool calls with no final report (issue 1). The 07-22
spec called the cause unverified and said "no workforce cap exists" — that
second claim is FALSE: `agents/builder.md` had `maxTurns: 150` in the audited
build (verified via `git show 187007b:agents/builder.md`), and a turn-capped
agent dies exactly this way — mid-loop, no final message. Root-cause
confirmation still needs the work-machine subagent transcripts, but the fix
must be cause-agnostic: any dispatch that returns without its final report —
turn cap, context exhaustion, crash — must be detected mechanically and
driven to completion, not read as success.

Verified harness facts the design builds on (real transcripts, session
481c7138): a sync Agent result carries `status: "completed"` and the final
report text in `toolUseResult.content` (array of text blocks); an async
launch stub carries `status: "async_launched"`, `isAsync: true`, and no
content. A killed agent physically cannot emit its final message, so a
required final-line marker's ABSENCE is a truncation signal that cannot be
gamed by the agent (rote compliance in the emitted value stays harmless: the
verifier and criteria still judge actual completion — the marker only proves
the report ended on purpose).

Five deliverables, in implementation order:

1. Criteria before code: dispatch guard requires an ACCEPTANCE CRITERIA block
2. Review after build: closeout ledger requires a reviewer after the last builder
3. Interrupted-dispatch detection: WORKFORCE_REPORT marker + PostToolUse guard
4. Role-contract edits (builder / verifier / reviewer / orchestrator / all specialists)
5. Skill mirror (agent-workforce SKILL.md + roles.md)

Out of scope: raising `maxTurns` (blind tuning until the work-machine
transcripts confirm the cap as cause — runbook step 4 of the 07-22 spec);
machine-local hooks; Codex profile regeneration beyond the doc edits here.

---

## 1. Criteria before code — dispatch guard

**Rule.** Every `builder` and `verifier` dispatch prompt must contain the
literal marker line `ACCEPTANCE CRITERIA` (same pattern as the existing
`PARALLEL_SAFE` / `WORKFORCE_BUDGET_ACK` markers). The orchestrator authors
the criteria before the builder is dispatched — from the architect's plan when
one ran, from the original request otherwise — and passes the same block
verbatim to the verifier. The builder's own tests are scaffolding for its
red/green loop; they never define the bar.

**Mechanism.** `hooks/agent-team-dispatch-guard.sh` (PreToolUse Agent,
fail-closed like its other checks): after the specialist allowlist check, if
the normalized type is `builder` or `verifier` and the prompt does not contain
`ACCEPTANCE CRITERIA`, exit 2 with a message stating the rule and its why
(criteria are authored upstream of the code so the builder is never the last
author of what done means).

**Tests (red first, `tests/test_dispatch_guard.sh`).** builder dispatch
without the marker → blocked; builder with it → allowed; verifier without →
blocked; executor without → allowed (unchanged).

## 2. Review after build — closeout ledger

**Rule.** Builder work needs an independent review verdict after the last
builder dispatch, exactly parallel to the existing fresh-verification check.
The cheap form is the reviewer's new fidelity mode (deliverable 4); risky
surfaces still get full review. Executor one-shots stay inside the
proportionality floor (unchanged).

**Mechanism.** `hooks/agent_team_closeout.py` `ledger_checks` gains check
1b, mirroring check 1: if `"builder" in roles` and no `reviewer` appears in
`order` after the last builder (and no `WORKFORCE_PAUSE`), block with the
demand to dispatch the reviewer against the delivered diff.

**Tests (red first, `tests/test_agent_team_closeout.py`).** builder +
verifier-after + no reviewer → block names the missing review; builder +
verifier + reviewer both after last builder → allow; reviewer before the last
builder only → block.

## 3. Interrupted-dispatch detection — WORKFORCE_REPORT marker

**Rule.** Every specialist report ends with the line
`WORKFORCE_REPORT: <role> | complete|partial|blocked` (within the last three
non-empty lines, so the Codex `WORKFORCE_PROFILE` final line can coexist).
`complete` = dispatched scope delivered with evidence; `partial` = deliberate
early stop with what-stands / what-remains; `blocked` = typed blocker per the
role contract. A missing marker is never any of these — it means the agent
was cut off.

**Mechanism.** New `hooks/agent-team-interrupt-guard.sh` (PostToolUse Agent
on the orchestrator, listed before the cost hook). Advisory guard, so
fail-OPEN on unparseable input (unlike the fail-closed PreToolUse safety
guard — this one cannot undo the call, only inform the orchestrator; wedging
every dispatch on a jq hiccup would cost more than it protects). Skip when
`isAsync == true` or `status == "async_launched"`. Otherwise join the text
blocks of `tool_response.content`; if no `WORKFORCE_REPORT:` line appears in
the last three non-empty lines, exit 2 with the reconcile-and-resume
instruction: treat the dispatch as interrupted, inspect the workspace
read-only (git status, commits, test state), re-dispatch the same role with
what stands + the remaining acceptance criteria marked RESUME; after two
interrupted resumes of the same phase, escalate with the evidence. Async
completions arrive as task-notifications no hook can inspect; the
orchestrator contract (deliverable 4) applies the same missing-marker rule by
instruction there.

**Tests (red first, new `tests/test_interrupt_guard.sh`).** marker on final
line → 0; marker on second-to-last non-empty line (profile line after) → 0;
no marker → 2 and stderr mentions RESUME; async stub → 0; non-Agent tool → 0;
invalid JSON → 0; content as plain string (defensive) → honored.

## 4. Role-contract edits

- `agents/builder.md`: the dispatch's ACCEPTANCE CRITERIA block is the bar;
  the builder's tests are its working instruments, never the definition of
  done; the report maps each criterion to state (met-with-evidence / not
  attempted / blocked); running low on budget means stop and report `partial`
  — a deliberate partial report beats a silent cut-off; marker line.
- `agents/verifier.md`: two duties per criterion — run the stated check, then
  attempt to falsify the claim behind it (entry path, adversarial input,
  does-it-actually-render) with read-only probes; report distinguishes
  "builder's checks pass" from "independently exercised"; marker line.
- `agents/reviewer.md`: new **fidelity mode** (cheap default for
  non-risky routes): compare the delivered diff against the original request
  text quoted in the dispatch; list every asked-for behavior as delivered /
  narrowed / missing; verdict. Full code-review mode unchanged for risky
  surfaces; marker line.
- `agents/orchestrator.md`: criteria authorship in dispatch mechanics (author
  before builder, verbatim to verifier, criteria are the task's completion
  ledger); routing table gains the fidelity check on the contained-build row;
  interrupted-dispatch protocol (missing marker ⇒ reconcile + RESUME
  re-dispatch, two-resume bound, applies to async completions by
  notification); completion claims trace to the criteria ledger.
- All other specialists (`architect, debugger, deployer, executor,
  researcher, ops, scribe, ticketer`): one sentence adding the marker line.

**Tests.** `tests/test_agent_frontmatter.sh` (or sibling text-drift test)
asserts every specialist file contains `WORKFORCE_REPORT:` and that
builder/verifier/orchestrator name `ACCEPTANCE CRITERIA`.

## 5. Skill mirror

`skills/agent-workforce/SKILL.md` and `references/roles.md` carry the same
contracts for skill-mode sessions (where no hooks run): criteria authored
before build, fidelity check before completion claims, marker + missing-marker
protocol, single-thread fallback explicitly labeled as running WITHOUT the
mechanical guards. Codex path: `WORKFORCE_REPORT` sits directly above the
existing `WORKFORCE_PROFILE` final line.

## 6. Full pipeline separation (added 2026-07-26, Jay's explicit model)

Jay's stated model: plan author, plan reviewer, feedback folder, test author,
implementer, tester, and fidelity checker are different parties — "nowhere to
hide." Mapping and enforcement:

- Plan authored (architect / orchestrator-authored linted criteria) — guard-enforced.
- Plan critiqued: ledger check 1a — a reviewer must sit between the first
  architect and the first subsequent builder.
- Findings folded: the architect (same accountable author) — convention, not hook.
- **Tests authored by a non-implementer: new `test-author` agent** (Jay chose
  design-routes-only, 2026-07-26): dispatched after plan critique with the
  reviewed plan + criteria; writes the acceptance suite under
  `tests/acceptance/` against the plan's fixed public interfaces; proves it
  red for the right reason; commits only test files. Ledger check 1a2 blocks
  design-route closeouts with no test-author between architect and first
  builder. The builder receives the suite read-only — an edit to it is a
  top-of-report reviewer finding and a plan-defect escalation, contract-level
  until commit-to-role attribution exists. Contained routes keep the
  lint-enforced criteria Checks as the upstream test layer (a test author
  with no plan would be guessing interfaces).
- Implemented (builder), tested (verifier, falsification duty), matched to
  the request (reviewer fidelity) — all ledger-enforced per §2.

## Designed limitations (stated, not hidden)

- **Criteria quality is mechanized to the falsifiability floor, no further.**
  The dispatch guard runs `lint_acceptance_checks.py` (the same lint plan
  criteria face) over the block: at least one tagged criterion required, any
  BLOCK finding (missing Check, tautological check, silent probe) blocks the
  dispatch. A vacuous "do the task" line therefore does NOT pass. What no
  hook can judge is semantic adequacy — whether formally-valid criteria
  actually cover the request; that lives in the reviewer's fidelity mode
  (which compares delivered work to the original request, independent of the
  criteria) and ultimately the human. Review rigor itself is likewise
  contract, not mechanism.
- **Async dispatches — mechanical at the source.** The PostToolUse guard sees
  sync results only; a background dispatch's completion arrives as a
  task-notification no hook inspects. Closed by `agent-team-report-guard.sh`:
  a Stop hook in every specialist's frontmatter (harness-converted to
  SubagentStop for dispatched subagents, per code.claude.com/docs hooks +
  sub-agents references) that blocks the specialist from finishing until its
  final message ends with the marker — enforcement at the specialist's own
  stop covers sync and async identically, before the parent consumes
  anything. Fail-open on `stop_hook_active` (never blocks twice, never
  wedges; harness hard-caps at 8 blocks regardless). Plugin mode routes the
  same guard via a `SubagentStop` entry in hooks.json (payload carries
  `agent_type`; foreign-plugin subagents are never policed). The Codex path
  enforces the same contract in `bin/agent-workforce-dispatch` (exit 3 with
  RESUME guidance when the real-task result lacks the marker; the marker-only
  policy preflight is exempt).
- **A killed agent fires no hooks of its own.** Marker absence is detectable
  wherever the result text lands, but nothing runs *at* the moment of a
  turn-cap death; detection is always at the consumption point.
- **A dead orchestrator is caught at the next start, not in real time
  (2026-07-26, issue #8).** The killed-agent limitation above has a partial
  close for the orchestrator itself: `session_start.py` (`reconcile_lines`)
  reads the single most-recent prior session transcript for the project and,
  when it shows specialist dispatches (`total > 0`) but its final message
  carries neither the closeout cost marker nor `WORKFORCE_PAUSE`, surfaces a
  `reconcile:` warning at the next launch. What this closes: a headless
  orchestrator that dies mid-closeout (e.g. `claude -p` exiting 0 on
  "Connection closed mid-response" after deliverables land but before the cost
  table prints) is no longer silent — the next session names it. What remains,
  stated plainly: (a) detection is deferred to the next session start, never
  real-time — nothing runs at the moment of death; (b) only the final report
  and telemetry are recoverable after the fact — the already-committed
  deliverables were never at risk, but any uncommitted tail dies with the
  process; (c) discovery inspects only the single most-recent prior transcript,
  so a plain session started before anyone reconciles will mask an older dead
  one — the deliberate trade that keeps the warning from nagging on every
  subsequent start forever; (d) the signal is a STATE, not a cause — any
  specialist-dispatching session that ends without a cost report or a pause
  trips it, which includes an enforcement-cap allow, a stale-read allow, and
  an operator closing an interactive session before the forced closeout, not
  only a genuine mid-process death. This is intentional: the state (no
  reconciled cost report) is what `scan_transcript` can actually detect; the
  cause is not, so the warning names the state and leaves the cause to the
  operator's inspection.

## Corrections to prior records

`docs/superpowers/specs/2026-07-22-innovation-awards-audit-fixes-design.md`
runbook step 4 says "no workforce cap exists — cause is still unverified".
Corrected in place: the cap exists (`maxTurns: 150`, present in 187007b);
cause still unverified until the work-machine transcripts are read.
