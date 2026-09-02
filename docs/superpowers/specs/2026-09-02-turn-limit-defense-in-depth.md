# Turn-limit defense in depth — decision record

**Date:** 2026-09-02
**Status:** BUILT AND VERIFIED, four of five real items. See "Final status" below —
read that section first; everything after "Provenance" is the reasoning trail that
got there, kept in full per this project's own evidence convention, not because it
is still the current answer.
**Author of this record:** Claude, acting on Jay's explicit instruction to grade and decide, not merely propose. See "Provenance" below.

## Final status (2026-09-02, end of session)

Branch `change/turn-limit-defense`, four commits, each with red-first tests run and
shown, and the full existing suite (34 shell test files, 90 python tests) re-run
green after every one of them:

1. **Turn-budget guard, built** (`fd14a8e`) — `hooks/agent-team-turn-budget-guard.sh`,
   registered on all ten policed roles. Once a dispatch's own turn count passes 85%
   of its role's cap, every further mutating command is refused with a written
   reason, except a commit or a read-only git command — turning today's silent
   hard kill into a chosen, reported stop wherever the dispatch is still able to act
   on the warning.
2. **Resume recap, built** (`3b550ed`) — `hooks/agent_team_dispatch_recap.py`, wired
   into both the interrupt guard's refusal message and `agents/orchestrator.md`'s
   own resume instructions. A resumed dispatch now gets the files, commands, and
   reasoning its predecessor's own transcript already holds, not a prose summary —
   the exact gap measured this session (a second reviewer attempt re-covering 61%
   of the first attempt's files before running out of turns itself).
3. **Scratch lane for judge roles — resolved as a non-issue, not built.** Building
   it is what caught that the lane check I had been reasoning about governs a tool
   path (Write/Edit) those four roles cannot reach; their real path (Bash) already
   allows a write outside every checkout, unconditionally, and all four roles'
   prose already says so. Nothing needed fixing.
4. **Sizing before dispatch, built** (`18ff6b6`) — one rule added to
   `skills/planning/SKILL.md`'s Scope section: size a dispatch by the real count of
   separately red-test-first fixes a group of tasks holds, not by its plan labels —
   grounded in the measured fact that Track C's five labels held about eleven real
   fixes and Track D's three held about eighteen, while Track A's eight labels,
   already atomic, held eight.
5. **Stop-reason telemetry, built** (`63f49a4`) — `hooks/cost_report.py` now writes
   `stop_reason` (`complete` / `max_turns` / `unknown`) into every per-dispatch
   telemetry record, mechanically derived, never guessed. This is what makes item 4
   below, and any future recalibration of a cap number, checkable against real
   data instead of another one-time guess.

**Left open, honestly, not papered over:** the narrow parsing defect in
`agent-team-worktree-rules.sh` (a bare digit read as a file path) has no
reproduction — only a paraphrase of what a real transcript showed blocked. The
guard's own header already documents its Bash-command matching as "best-effort by
construction," an accepted limitation, not a promise of catching everything. Fixing
a specific line without the exact command that triggered it would be a guess
dressed as a fix, which this record has already corrected out of itself twice.
This item stays open until a real repro exists; it is not one of the five graded
above, and was never promoted past "confirmed by symptom only."

## Provenance

Jay's own words, this session: "I'm not going to grade. You are going to grade.
Decide how you want to grade. Decide what defense in depth looks like. Decide
what 'good' and 'done' mean in context. Understand how you are going to test
and confirm work once complete."

Everything under "Grading," "Target shape," "Good and done," and "Test and
confirm plan" below is therefore a DECISION, not a proposal — Jay named the
authority and handed it over in this session. The build order that follows
from the grading is also decided. Actually writing the code is a separate,
later step (see "Next step," end of file) and is not yet done.

## The problem, restated in one paragraph

Every specialist role this framework dispatches (architect, builder, debugger,
deployer, executor, ops, researcher, reviewer, scribe, test-author, ticketer,
verifier) has a hard cap on the number of turns a single dispatch may take,
set once in that role's own file. A dispatched agent cannot see this cap or
its own count against it. When the cap is hit, the agent is stopped mid-step,
with no chance to save its place or say what it was doing. The record search
run this session found this has happened, confirmed, dozens of times, across
at least three separate codebases, hitting the builder, architect, reviewer,
scribe, test-author, and verifier roles, as recently as today. In one task, a
reviewer dispatch hit its own cap twice in a row across two resume attempts.

## The one fact that changed since the last message

Several of the newly found cut-offs carry the exact words, already produced
by the running system itself: "stopped at its N-turn limit." Combined with
every single Tier-1/Tier-2 example landing on the exact numeric cap for its
own role, the TRIGGER is no longer an open question. It is confirmed: a fixed
turn-count wall stops the agent. That is not the same fact as the CAUSE — the
reason real work needed that many turns before the wall was ever reached —
and this record wrongly treated the two as one fact in its first version. See
"Correction" below.

## Correction (added after Jay's challenge, before any build)

Confirming the trigger is not confirming the cause. Two facts already in the
evidence gathered this session should have blocked the grading below from
being trusted as-is:

- A scribe dispatch hit its 40-turn cap writing one status note. A verifier
  dispatch hit its 40-turn cap right after confirming one test tier passed.
  Neither task should need 40 real, productive steps. Something is consuming
  turns that is not the stated task.
- A reviewer dispatch hit its 60-turn cap once, then hit the identical
  60-turn cap again on its very next, narrowed resume. If the second attempt
  spent its turns re-covering ground the first attempt already covered, the
  cause is waste, not workload — and no item in the grading below was built
  to fix that.

A separate transcript read this session (the AWS/show-year debug run) showed
an orchestrator's closing message rejected and forced to restate itself three
times by a hook checking exact wording — turns spent on format, not on the
task. The same kind of exact-marker enforcement runs on every specialist
dispatch via `agent-team-report-guard.sh`. Whether this pattern also eats
real turns inside specialist dispatches is not yet checked.

**The grading and tiers below are demoted from decided to provisional** until
a turn-by-turn read of a sample of real overrun dispatches — the scribe, the
verifier, both reviewer attempts, and a genuinely large builder task as a
comparison — shows where the turns actually went: oversized real work,
retry/permission-error loops, redundant re-exploration, hook-forced
restatement, or something else. That read is dispatched now, as background
research; its result will correct or confirm the tiers below before anything
in "Next step" is authorized to start.

## Correction 2 (the cause did not need that read; it was already found)

Sending agents to count turn-buckets was still hunting for a mechanism, one
layer down from the mistake Jay had already named. The cause was already
proven, not hypothesized, in the first search this session ran:

- Every cap in `agents/*.md` was set once, by the project's own commit
  history, "verbatim from the brief" — no measurement, no stated reason tied
  to any real task.
- The 2026-07-22 incident (Track C/D) implicated these exact caps. The
  2026-07-26 record named the cap as "the leading hypothesis," declared
  tuning it out of scope until someone read the real transcripts to confirm
  it, and no one did — not for over a month, and not by this session either,
  until Jay forced a second look.
- No cap has changed since the day it was first set, including after that
  incident, including through everything found in this session, until now.

**The cause is a control with no feedback**, at two distinct timescales, not
one problem:

1. **Real-time gap.** The agent doing the work is never told how much of its
   own budget remains. It cannot self-manage what it cannot see.
2. **Calibration gap.** Whoever sets the number is never told, from real
   usage, whether it was right. This project has no standing practice that
   closes this loop — the number is set once, at birth, and never revisited.

Every symptom in this record — the silent kill, the lost work, the manual
restart, the cost, the trust — is downstream of these two gaps, not of any
one dispatch's mix of productive versus wasted turns. The two background
agents reading turn-buckets will still return useful secondary detail (how
much of the real-time gap's damage, in the cases they read, is genuine
oversized scope versus waste) — that shapes HOW the real-time gap gets
closed. It does not decide WHETHER either gap is real; both already are.

**This also means the grading in "Grading — the result," above, is itself an
unmeasured judgment call** — ranked by instinct, the same pattern named as
the cause. It is corrected below, anchored to the two gaps instead of to
seventeen items graded by feel.

### Grading, corrected

**Build first — this closes the calibration gap, and until it exists, no
other grade in this file is more than a guess:**
- Item 14 — a real, named stop-reason and turn-count field in the standing
  per-dispatch cost record, for every dispatch, every role, from now on.
- A new item, not on the original list: a standing practice that reads that
  field back against the caps on a recurring basis, and is the one place a
  cap number is allowed to change. Not a one-time fix; the missing loop
  itself, made durable.

**Build next — this closes the real-time gap, and is where the turn-bucket
data actually matters:**
- Item 3 — show the agent its own turn count against its cap.
- Item 6 — force a clean, reported stop before the hard cap.
- Item 15 — size a resume by evidence of what remains, once item 14 exists to
  supply that evidence.

**Everything else in the original seventeen (splitting oversized work before
launch, fixing known retry loops, checkpointing, automatic resume dispatch,
applying this to every role, widening the shared eval) stays real and worth
building, but every one of them is now a downstream detail of closing the two
gaps above — not a peer to them, and not gradeable with any confidence before
the calibration gap has produced its first real numbers.**

## Correction 3 (Jay's challenge: is improperly sized work the real cause)

"Control with no feedback" was the wrong altitude. It explains why a known gap
sat unfixed for over a month. It does not explain why any single dispatch ran
over its cap. That second question has a direct, already-evidenced answer for
the largest, costliest incidents, and it is not the same claim as either gap
above.

**Confirmed, not hypothesized, for the builder-scale incidents:** the Track C
builder's own record (`docs/analysis/2026-07-22-innovation-awards-workforce-
issues.md`) lists six already-defined tasks completed inside one dispatch —
C1, C2a, C2b, C2c, C3, G14 — plus C4 left half-done and C5 never started. This
project's own planning rule already defines the right-sized unit: "the
smallest unit that carries its own test cycle and is worth a fresh reviewer's
gate." That rule was not missing. Dispatch ignored it and handed a bundle of
seven-plus tasks to one builder call instead of one task per call. The same
shape almost certainly explains the four builder dispatches that each hit
exactly 150 in session `c44c44f0` — each was handed a build-sized chunk
("Implement media normalization gate," etc.), not a single planning-sized
task.

**Not yet confirmed, for the narrow-role incidents:** the scribe writing one
status note, the verifier confirming one test tier, and the reviewer hitting
the identical 60-turn cap twice do not obviously bundle several tasks the way
a whole "track" does. Whether these are also a sizing failure (a resume that
was never actually made smaller) or waste inside one genuinely single-sized
task is exactly what the two background transcript reads already running
will answer — not invented follow-up work, the same two reads dispatched
before this correction.

**Grading, corrected again — sizing before dispatch moves to first, ahead of
the calibration-loop item, for the confirmed cases:**

1. **Build first, no new measurement needed:** enforce one planning-sized
   task per dispatch at the point the orchestrator hands work to a builder
   (or any role) — the sizing unit already exists in `skills/planning/
   SKILL.md`; the fix is making dispatch respect it instead of bundling.
2. **Build alongside it:** item 14, the stop-reason and turn-count field —
   needed to confirm (1) actually worked, and to tell, for the narrow-role
   cases, whether the cause there is sizing too, or something else.
3. Everything else stays ordered as in "Grading, corrected" above, downstream
   of these two.

The calibration-loop gap (no standing practice ever revisits a cap against
real data) is demoted from co-primary to what it always was: the reason this
specific, already-evidenced sizing failure was named in this project's own
record on 2026-07-22 and then left unfixed past today.

## Correction 4 (checked the client project's own plan; item count was the
wrong measure)

The 2026-07-22 orchestrator session transcript is gone from disk — no
`f7e1d4db-6f50-4b85-bc32-1c648d543350.jsonl`, no subagents directory —
so "was Track C one continuous dispatch" can no longer be confirmed against
that primary source. But the client project's own plan for that day survives:
`/Users/jay/claude/innovation-awards/docs/product/handoff-prompt-bug-fixes.md`
(very likely, not yet word-for-word certain, the plan behind these four
tracks, given the matching date and track letters).

Item count is the wrong measure, and checking it changes the finding:

| Track | Numbered items | Overran? | What's actually inside the items |
|---|---|---|---|
| A | 8 (A1-A8) | No | Each item is one bug, one fix — already atomic |
| B | 4 (B1-B4) | No | Each item is one fix |
| C | 5 (C1-C5) | Yes | C2 hides 3 sub-fixes; C5 hides 5 unrelated fixes under one label |
| D | 3 (D1-D3) | Yes | D1 hides 9 separate document fixes; D2 hides 5 test-hardening fixes |

Track A has the most numbered items and did not overrun. The measure that
actually lines up with the overrun is the count of separately-testable
fixes hiding under each label — not the label count itself. Track C's five
labels hold on the order of eleven real fixes; Track D's three labels hold
on the order of eighteen. Track A's eight labels hold eight.

**The corrected primary cause:** the plan groups fixes by subject area, for a
reader, not by how much red-test-first work each one costs. Nothing between
writing that plan and dispatching a builder at it ever translates the first
grouping into the second. "One planning task per dispatch" (Correction 3) is
therefore underspecified — it assumes the plan's own item numbers are already
the right-sized unit, and this plan shows they often are not. The fix has to
size against the count of separately-testable fixes, not against however the
plan happened to label them.

## Correction 5 — two full background reads landed; this has two shapes, not one

Two dispatched reads, each given specific real transcripts to read in full and
classify turn by turn, both completed. Their combined result is the most
solid evidence in this record, and it splits the problem in two.

**The counting mismatch, resolved as far as it can be.** The narrow-role read
counted a raw JSONL assistant-message entry as one turn; the builder-scale
read counted one reply (a unit that can chain several tool calls) as one
turn, and confirmed this is the enforcement mechanism's own unit by counting
unique reply identifiers — all four builder files hold exactly 150, matching
the known cap exactly. Removing the narrow-role read's "pure reasoning" bucket
(almost entirely the second half of a reply-id pair, not a distinct step)
brings most of its six transcripts close to their real caps, but not all:
one (the second reviewer attempt) lands exactly on its 60-turn cap; four
others still run over even after the correction (verifier ~61 against 40;
test-author ~93 against 80; first scribe ~57 against 40; first reviewer
attempt ~73 against 60; second scribe ~61 against 40). That residue is not
explained by anything in this record and is left open, not guessed at.

**Shape 1 — large, builder-scale work (measured, not estimated).** Four full
150-turn builder transcripts were read and classified end to end. Combined:
95.3% productive, 4.0% error/retry, 0.5% redundant, 0% format/process, 0%
pure reasoning. No transcript's waste exceeded 7%. Three of the four had a
finished, passing piece of work sitting uncommitted when the cutoff hit. This
confirms Correction 3/4 directly: the dominant cause is real, necessary
engineering work exceeding the budget, not waste. Waste-reduction fixes have
almost nothing to act on here.

**Shape 2 — narrow-role work (measured, mixed causes, four distinct
mechanisms, each independently confirmed):**

1. **Genuinely oversized single tasks**, same as Shape 1 but on a smaller
   role's smaller budget: the verifier was handed sixteen pass/fail
   conditions, a full suite run, and a browser-side suite, in one pass; the
   test-author was handed six files and eight new tests.
2. **A documentation gap, not a hook defect.** `agent-team-worktree-guard.sh`
   deliberately blocks judge-type roles (verifier, reviewer, debugger, ops)
   from writing anywhere inside any git checkout — verified by reading the
   hook itself, and correct by design: a role that judges code must not be
   able to change the code it judges. The hook already treats a location
   outside every checkout as legal for exactly this purpose. Neither role's
   own instructions say so, so both kept retrying inside the checkout and
   kept being correctly refused, at a real cost — roughly 15-20 turns in two
   of the six transcripts read.
3. **A real, narrow parsing bug**, separate from the policy above: the same
   hook was seen misreading a bare digit, "0", as a file path and blocking a
   command that wrote no file at all.
4. **A resume mechanism that discards real progress.** The second reviewer
   attempt was explicitly told not to repeat the first attempt's ground and
   to budget its turns. It still reopened 61% of the same files and ran some
   of the same commands word for word, because its resume dispatch carried
   forward only a short prose summary, not the first attempt's actual
   findings — then ran out of turns re-confirming something already settled,
   instead of writing down what it knew.

One earlier claim in this record's chain of evidence was itself wrong until
this read caught it: the test-author dispatch was reported as stopping with
"six test files staged but uncommitted." The transcript shows it committed
successfully three turns before the file ends and simply ran out of room
before a closing line. That claim came from a summary two steps removed from
the raw transcript. It is corrected here, and it is a caution about trusting
any layer of this record that has not been checked against its own source.

## Final priority, corrected by measured leverage (supersedes every prior
grading in this file)

1. **Fix the resume mechanism** to carry forward a stopped dispatch's actual
   findings, not a prose summary — confirmed severe (Shape 2, item 4), cheap
   to state precisely now that the failure is on record.
2. **Tell every judge-type role, in its own instructions, where the one
   legal scratch location outside any checkout already is** — closes Shape
   2, item 2, with no hook change needed.
3. **Fix the specific parsing defect** that reads a bare digit as a path
   (Shape 2, item 3) — narrow, mechanical, low risk.
4. **Size work against the receiving role's real turn cost before dispatch**,
   calibrated from the numbers measured in this record (a video-normalization
   build alone used most of a 150-turn budget; a three-piece recovery-ladder
   build fit cleanly in the same budget) — the whole story for Shape 1, and
   part of it for Shape 2's oversized-task cases.

Everything else from the original seventeen items (live turn count shown to
the agent, a forced clean stop before the hard cap, checkpointing, the
stop-reason telemetry field, applying all of this to every role, widening the
shared eval) stays valid as further layers, now correctly understood as
sitting behind these four — which are the only four with real measurement
behind them, not a grade assigned by feel.

## Correction 6 — stress test of the final four, against Jay's three
questions (does it hold, is it defense in depth, is it testable to success)

**Does it hold? Two of the four items had a gap, found by checking rather
than asserting.**

- **The resume fix assumed the stopped agent's findings are already sitting
  somewhere retrievable.** They are not — Correction 2 already established a
  hard maxTurns kill lets the agent write nothing at that moment. The real
  fix is a component that reads the surviving raw transcript after the kill
  and extracts what the agent had already worked out, not merely "pass
  forward what it found." That extractor does not exist yet and is its own
  piece of work.
- **The scratch-lane fix assumed a legal lane already exists for judge
  roles.** Checked `hooks/agent-team-lanes.json` directly: `role_lanes`
  defines a lane for `scribe`, `architect`, and `test-author` only. Verifier,
  reviewer, debugger, and ops — the four roles that actually hit this
  problem — have no lane at all. The fix is building one, then pointing
  those roles at it, not a documentation change alone.
- **The parsing bug remains confirmed only by its symptom.** A search this
  pass did not locate the exact faulty line in `agent-team-worktree-rules.sh`.
- **Sizing before dispatch holds for decomposable work, not for all of it.**
  Three of the four measured builder transcripts support splitting cleanly.
  The fourth (the video-normalization build: frame-timing math, a parser, a
  19-point check, and a similarity measurement) reads as one tightly coupled
  piece; splitting it may not lower its total turns, and could add cost from
  re-reading the same design context in each split piece.

**Does it provide defense in depth? Not as last ranked.** "Show the agent its
own turn count" and "force a clean stop before the hard cap" had been pushed
into an unranked afterthought. That is the gap: those two are what turn
today's silent, hard kill into a voluntary, self-reported stop — which is
what would make the resume fix cheap and reliable, instead of needing to
reconstruct an agent's thinking from a raw, truncated file after the fact.
With nothing between prevention and recovery, a wrong sizing guess still goes
straight to a hard kill. This same layer is also the only real answer for the
one case sizing cannot fully solve — a tightly coupled build that resists
splitting.

**Is it testable to success? Unevenly, and that should stay visible.** The
resume fix, the new lane, and the parsing bug are each testable to a clean
pass/fail with one built scenario, once each is actually buildable per the
gaps above. Sizing before dispatch is NOT provable "done" from any single
test run — the only honest check is a rate, measured over real dispatches
going forward, using the stop-reason field (item 14), which this record had
pushed down to a lower tier. Calling sizing finished without that
measurement in place repeats the exact mistake that put an unmeasured 150 in
place at the start of this whole record.

## Final priority, corrected again after the stress test

1. Restore and pair, at the top, with sizing: **show the agent its own turn
   count, and force a clean, reported stop before the hard cap.** This is
   the graceful-degradation layer that was wrongly demoted, and it backstops
   both the resume fix below and the one task shape sizing cannot split.
2. **Build the transcript extractor** the resume fix actually depends on —
   not "pass forward findings," but the specific component that reads a
   killed dispatch's raw transcript and produces what it had already found.
3. **Build a real write lane for verifier, reviewer, debugger, and ops**,
   outside any git working tree, then point those roles at it — the
   documentation fix only works once this exists.
4. Fix the specific parsing defect, once its exact line is found.
5. **Size decomposable work before dispatch**, using the measured numbers in
   this record, paired always with item 1 above for the work that does not
   decompose.
6. **Add the stop-reason and turn-count telemetry field** — no longer a
   background item: it is the only way item 5 above is ever testable to
   success, not merely testable to a passing synthetic scenario.

## Correction 7 — the top item was not buildable as designed; checked the
hook capability directly rather than assume it

Jay asked, directly, whether confidence in building this exceeds confidence
that thirty seconds of his own review would find a fatal flaw. Checking
`~/.claude/skills/hook-architect/hooks-reference.md` before answering found
one: injecting visible text into a running agent's own context
(`additionalContext`) is confirmed working for exactly two events —
`SessionStart`, once, and `UserPromptSubmit`, once per submitted prompt. A
dispatched subagent receives one initial prompt from its dispatcher and then
loops on tool calls on its own; nothing in it repeats `UserPromptSubmit` as
it runs. **Item 1's live turn count, as designed, cannot be built.**

What the same reference confirms IS buildable, using a pattern this
project's own hooks already run successfully: a hook before each tool call
that computes the turn count from the transcript, and once a threshold is
crossed, blocks one tool call with a written reason — the same
block-with-a-stated-reason mechanism the worktree guard already uses. That
gives a forced pause and a chance to write a real closing report near the
cap. It does not give a continuously visible countdown; item 1 in "Final
priority" is corrected to this narrower, threshold-triggered version.

**This is the second time in one review pass that checking a claim, instead
of trusting the previous pass's own reasoning, found the previous pass wrong**
(the lane-config claim in Correction 6 is the first, and is itself still
unresolved — whether judge roles need a newly configured lane, or whether the
existing "outside every working tree" rule already covers them independent
of the lanes file, has not been settled). Six corrections in, the record's
own history is the honest answer to "is this ready": no version of it has
survived a real check yet, including this one.

## Correction 8 — built, not just reasoned about; two items resolved by
building them

Built in an isolated worktree (`change/turn-limit-defense`), against the
real hook and the real test suite, not against a description of either.

**The scratch-lane item (Correction 5/6/7) was chasing the wrong code path,
and turned out to need no fix at all.** Verifier, reviewer, debugger, and ops
hold no Write, Edit, or NotebookEdit tool in their own frontmatter — only
Bash. The lane check in `write_verdict()` this record checked twice governs
the Write/Edit-tool path, which these four roles can never reach. Their real
path is the separate Bash-mutation rule in the same guard file, which already
allows a write to anywhere outside every git working tree, unconditionally,
with no lane required — confirmed already covered by an existing, passing
test (`tests/lib/worktree-guard-shell-cases.sh`, "diagnostic: scratch
directories outside every working tree allow"). Further: all four agent
files (`agents/verifier.md`, `reviewer.md`, `debugger.md`, `ops.md`) already
state this in their own prose, in language close to the guard's own refusal
message. There was nothing to build. The real, still-open question this
leaves — why an agent with that instruction still targeted a path inside the
checkout during the real incident — is not answered by this record and is
not papered over with a documentation change that has nothing to fix.

**The stop-reason telemetry field (item 6) is now real: built, tested,
committed.** `hooks/cost_report.py` reads each dispatch's own raw transcript
and writes `stop_reason` — `"complete"` (its own closing `WORKFORCE_REPORT:`
marker present), `"max_turns"` (no marker, request count at or past that
role's own cap from `agents/<role>.md`), or `"unknown"` (neither, stated
honestly rather than guessed). Four new red-first cases in
`tests/test_cost_report.sh`, confirmed failing against the unmodified code
(verified via a real stash-and-restore, not assumed) and passing after the
fix. The full existing suite — 34 shell test files, 82 python tests — re-run
afterward and green. Committed: `63f49a4`, branch `change/turn-limit-defense`.
`docs/telemetry/README.md` documents the field.

This is the first item in the whole record with real, run evidence behind
"done," rather than a grade. The other five items in "Final priority" have
not been built and carry no such evidence yet.

## Grading — the rubric

Each candidate fix (numbered 1-17, carried over from the prior message in this
session) is graded on four questions, in this order:

1. **Does it need the cause confirmed first?** Answered above: no longer a
   blocker for any item.
2. **Does it help one role or every role?** A fix that only touches the
   builder role's number is narrow; the record shows six roles affected.
3. **Can it be built now, with what exists, or does it need something else
   built first?** This produces the tier.
4. **Does it match or fight the original design intent?** The cap was written
   down on day one as "runaway control." A fix that removes the cap outright
   fights that intent; a fix that gives the agent visibility, or narrows work
   to fit, keeps the control while removing the silent failure.

## Grading — the result

**Already answered, no build needed:**
- Item 12 (confirm the real cause before acting) — done by this session's own
  record search.

**Tier 1 — build now. No blocker. Helps every role.**
- Item 3 — show the agent its own turn count against its cap.
- Item 6 — force a clean, reported stop before the hard cap, paired with 3.
- Item 7 — check that work stays in small, saved steps throughout (mostly
  already the standing rule; this makes it checked, not just written down).
- Item 2 — split oversized work into right-sized dispatches before launch.
- Item 5 — fix known turn-wasting patterns (a blocked command retried in a
  loop instead of stopping and asking).
- Item 10 — make the resume step an automatic action, not a rule the lead
  agent has to remember.
- Item 14 — add a real, named stop-reason field to the standing per-dispatch
  cost record.
- Item 16 — apply every item above to all twelve roles, not only builder.
- Item 17 — widen the existing test file so it also covers a second cut-off
  on a resumed dispatch, since that is now a confirmed real case.

**Tier 2 — build after Tier 1 lands and produces real numbers.**
- Item 4 — size the cap by the task, not by a single fixed number per role.
- Item 9 — close the detection gap for background dispatches (needs item 14's
  field to exist first).
- Item 11 — auto-save the agent's exact place at the stop point (needs item 6
  to exist first, so there is a clean point to save).
- Item 15 — size a resumed dispatch by real evidence of what remains (needs
  item 14's data to measure "what remains" against).
- Item 1 — raise any one role's cap, only once item 14's numbers show which
  cap is actually too tight, for which role, and by how much.

**Tier 3 — not yet.**
- Item 13 — a cheap check before an expensive resume. Only worth building
  once item 10 is running at real volume and its own cost becomes worth
  cutting.

## Target shape — defense in depth

Defense in depth means no single layer is trusted alone; each layer below
exists to catch what the layer before it missed. Every layer has at least one
built item, so removing any one layer still leaves the failure caught, only
one step later and one step more expensive.

| Layer | Job | Built from |
|---|---|---|
| 1. Prevent | Stop the cap from being hit at all | Items 2, 5, 16 |
| 2. Degrade softly | Turn a silent hard kill into a chosen, reported stop | Items 3, 6, 7 |
| 3. Detect, labeled | Know a cut-off happened, and why, without guessing | Item 14 (the label mostly already exists in the raw log per the new fact above; the gap is saving it) |
| 4. Recover, reliably | Get back to work without repeating the same failure | Items 9, 10, 15 |
| 5. Measure and correct | Turn scattered incidents into a standing number, and revisit settings against real data, not guesses | Items 1, 4, 14, 17 |

## Good and done

**Good** (the target state, checkable, not aspirational):
- No dispatched agent's work is ever silently lost. Every stop, whatever the
  cause, leaves either a written report or a state clean enough to resume
  from without guessing.
- No agent is blind to its own limit. Every dispatched agent can see, in its
  own working context, how much run room is left.
- The same piece of work does not hit the same wall twice, unseen. A resume
  that is about to run out of room again is caught and escalated, not
  silently repeated a third time.
- Every cut-off is a counted fact, not a story pieced together afterward from
  a raw session log, the way this session had to.

**Done** (per item, before it counts as shipped):
- The change is committed.
- A test proves the specific failure it targets is now either prevented or
  caught and handled — not merely that the code runs.
- The shared eval file for this failure (`evals/agent-workforce/
  scenario-completion-drive.md`) covers that exact case, with a recorded
  passing run.

## Test and confirm plan

1. **Extend the existing eval before writing new production code.** The
   eval already tests one cut-off and a correct resume. Add two new cases to
   it, matching real incidents found this session: (a) a resumed dispatch
   hits its own cap a second time — the correct behavior is escalation, not a
   silent third try; (b) a dispatch nearing its cap receives its own turn
   count and stops itself cleanly with a partial report, instead of being
   killed mid-step.
2. **Do not trust a passing eval alone.** The eval already passed once, in
   the recorded run this session found, while real incidents still happened
   afterward, including one today. So after each Tier 1 item ships, confirm
   it against the next real dispatches, not just the synthetic case — the
   same way this session found real incidents, by matching each dispatch's
   request count against its role's cap in the standing cost record.
3. **Use a count, not a date, as the confirmation gate.** Watch the next set
   of real dispatches per role, after item 14's stop-reason field exists,
   and confirm the rate of unlabeled or repeated cut-offs actually drops. A
   fix that only passes its own eval and is never checked against real
   dispatches is not done, per the definition above.
4. **Recalibrate on data, not on this session's guesses.** Items 1 and 4
   (any cap number itself) are only decided once item 14's real numbers name
   which role, and by how much, is actually too tight — not before.

## Next step

This record is the decided design. Building it is Tier 1 work, nine items,
each needing its own red-first test per this project's own TDD rule. That is
implementation work, done in an isolated worktree per this project's own
convention, not a chat answer — it has not started yet and is the next piece
of work in this project.
