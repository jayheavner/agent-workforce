# Workspace isolation: the work register

**Goal.** Make it structurally impossible for two agents — in one session or in
different operating-system processes — to write into the same working directory, without
refusing honest work.

**Architecture.** The unit of isolation becomes the *change*, not the agent: one linked
git worktree per change, shared by every agent contributing to that change, with at most
one live writer in it at a time. Ownership is a durable fact on disk — a **timecard**
file per claim in a machine-scoped, per-project **work register**, created with an
exclusive-create that the filesystem itself serialises — so guards read facts instead of
inferring identity from conversation history. Worktree creation and adoption are
performed by hooks as a side effect of a declaration in the dispatch; release and
integration are performed by one workforce command the executor runs, and the Stop hook
only verifies that it happened. No agent runs a raw mutating git command against the
shared checkout.

**Tech stack.** Bash hooks + `jq` (existing guard convention), Python 3 only where a
hook already uses it, POSIX filesystem primitives for exclusion. No new dependencies,
so `policy:dependency-freshness` pins nothing in this plan.

## Global constraints

- `policy:workspace-isolation` — resolved from **project policy** (`policy/KEYS.md:20`),
  verbatim: *"one unique worktree per builder, created before any code is touched
  (consumers: planning, tdd, debugging, finishing-a-branch)"*. **This plan amends that
  key** (Task 7): the unit becomes the change, not the builder, and creation moves from
  the orchestrator to a hook. The existing wording governs every dispatch until the whole
  of Stage 2 is integrated — including the dispatches that implement this plan.
- `policy:dependency-freshness` — resolved from **project policy**
  (`policy/KEYS.md:19`); no dependency is added or pinned by this plan, so the key is
  consulted and not exercised.
- `policy:closeout-integration` — **no value is pinned in this checkout.** The session
  executing this plan proceeds on `push` (push to `origin/main` at closeout). Because a
  push makes a partial state the default for every future session, integration cadence is
  a design decision here, not a closeout detail: see decision 9.
- Hooks are pinned per session (`hooks/agent-team-pin.sh`), so two guard builds may read
  one register concurrently. Every register format change is additive and carries the
  `v` field; a reader that does not recognise a field preserves it untouched.
- **Agent documents are not pinned.** `hooks/agent-team-pin.sh` versions hooks only.
  `install.sh` copies `agents/*.md` flat into `~/.claude/agents/` (install.sh:694), so an
  install swaps role prose under a running session while that session's guards stay
  pinned. Directive prose and the guard that enforces it must therefore reach
  `origin/main` in the same push (decision 9).
- Tasks are ordered, and every task's files are disjoint from every other task's except
  where a later task extends a file an earlier task in the same stage created or
  modified.
- **Test output convention (new, and the plan depends on it).** Every test file this plan
  creates or rewrites prints one line per case in exactly this shape — `PASS [<label>]`
  for a passing case, `FAIL [<label>]: <why>` for a failing one — and keeps a trailing
  `passed=<n> failed=<n>` summary. The acceptance criteria below count those labels, so a
  case that is silently dropped fails its criterion instead of passing by absence.
- **No test writes the real register.** Every test sets
  `AGENT_TEAM_REGISTER_DIR="$WORK/register"` inside its own temporary fixture, and every
  test that exercises telemetry sets `AGENT_TEAM_TELEMETRY_DIR` the same way. A test that
  leaves either unset is a defect, because it would mutate the machine's live register.
- Security pass: the register stores no credentials; timecards hold a session id, a
  process id and its start time, a change slug, paths, a ref name, and timestamps only.
  Refusal messages quote paths and slugs, never file contents. The register directory is
  created with mode 700.
- Never the word for a movable git pointer: the unit of isolation is the worktree, and
  history is named by ref (`main`, `origin/main`, `refs/heads/change/<slug>`).

## Mutation scope

- **Dependencies installed:** none.
- **Files created:** `hooks/agent-team-register.sh`, `hooks/agent-team-register-lib.sh`,
  `hooks/agent-team-register-writer.sh` (added 2026-08-17, Stage 1's code review — the
  exclusive take a removal goes through, and the writer slot built on it), `hooks/agent-team-workspace.sh`, `hooks/agent-team-register.json`, `tests/lib/concurrency.sh`,
  `tests/test_register_concurrency.sh`, `tests/test_register.sh`,
  `tests/test_register_lifecycle.sh`, `tests/test_register_races.sh` (added 2026-08-17,
  Stage 1's code review — the unit tier split three ways: decisions, a card's lifetime, and
  the real-process race tier), `tests/lib/register-fixture.sh` (added the same pass — the
  fixture and case-runner the three files above share), `tests/lib/slow-claimant.sh` (added
  the same pass — a real claimant process the race tier uses to hold the dead-card judgment
  open long enough to force the worst-case interleaving on demand),
  `tests/test_workspace.sh`, and — authored by the test-author, not by a builder —
  `tests/acceptance/test_workspace_isolation.sh` (the directory `tests/acceptance/`
  does not exist yet; creating it also activates the worktree guard's existing
  read-only-acceptance-suite rule, `agent-team-worktree-guard.sh:184`–`:201`).
- **Files modified:** `hooks/agent-team-dispatch-guard.sh`,
  `hooks/agent-team-worktree-guard.sh`, `hooks/agent_team_closeout.py`,
  `tools/worktree-hygiene.sh`, `install.sh`, `policy/KEYS.md`, `README.md`,
  `agents/*.md` (eleven of the thirteen; `agents/researcher.md` and `agents/ticketer.md`
  are untouched — see Task 6 and Task 7), and the test files
  `tests/test_dispatch_guard.sh`, `tests/test_worktree_guard.sh`,
  `tests/test_agent_frontmatter.sh`, `tests/test_closeout_hook.sh`,
  `tests/test_worktree_hygiene.sh`.
- **Files deleted:** none.
- **State touched outside the repo, at run time:**
  `~/.claude/state/agent-workforce-register/<project-key>/<slug>.json` (created,
  rewritten, deleted by the register), and one appended line per refusal in
  `~/.claude/logs/agent-team-telemetry/guard-blocks.jsonl` (existing behaviour). Linked
  worktrees are created under `<project>/.claude/worktrees/`, already gitignored
  (`.gitignore:6`).
- **Not touched by the executing session:** `install.sh` is not *run* by this task, and
  the launcher is not re-run. See "Executing this plan under the old rules".

## Decisions resolved by the panel (2026-08-17, debate mode), with amendments

1. **Owner and writer are separate fields.** A timecard names the change's owning
   session *and* the currently-writing agent slot. Two builders repairing one change
   share the tree but never hold the writer slot at once. (Adzic: H1 removed the
   accidental serialisation that per-builder trees provided.)
   *Amended 2026-08-17:* the writer entry carries its **own** liveness — a heartbeat and
   a TTL — because a builder subagent that dies mid-task does not kill the session
   process whose pid the timecard records, so pid liveness can never release a writer
   slot. See Task 4, `register_writer_acquire`.
   *Amended 2026-08-17, second pass (Stage 1's code review):* "separate fields" was read
   too literally — the writer slot was implemented as a field (`writer`) inside the
   timecard, set by a read of the existing value followed by a write of the new one. That
   read-then-write is not atomic: two guards acquiring the slot in the same instant both
   read an empty `writer`, both merged their own name in, and the second write won while
   both callers were told they had it — reproduced at five winners out of eight racers in
   review. The slot is now its **own file**,
   `<register-root>/<project-key>/writers/<slug>.json`, created under `noclobber` — the
   same atomic exclusive create the claim itself uses — and released by unlink. The
   timecard's `.writer` field survives, but only as a **mirror**: the operator view and the
   staleness heartbeat read it, and it is never what `register_writer_acquire` decides
   against. See Task 2, `register_writer_acquire` and `register_writer_release`.
2. **Workspace administration is a hook side effect, not an orchestrator command.**
   The orchestrator declares `CHANGE: <slug>` in a dispatch; the dispatch guard claims
   the timecard, creates or adopts the worktree, and rewrites nothing else. This resolves
   Fowler's contradiction — the orchestrator can lose Bash and still get workspaces — and
   removes the class of failure where a malformed or missing path burned seven dispatches.
   *Amended 2026-08-17:* the side effect covers **creation and adoption only**. Release,
   integration, and tree removal are performed by one explicit command
   (`agent-team-workspace.sh integrate`) that the executor is dispatched to run, because
   the closeout hook fires on **every** Stop — a mid-task pause that integrated unfinished
   work and deleted a live workspace is the failure that amendment prevents. The Stop hook
   verifies the outcome and mutates nothing (Task 8).
3. **One file per claim, created with `O_EXCL`.** Mutual exclusion is the filesystem's
   atomic create, not a lock file and not an append to a shared list. This answers
   Nygard's lost-update objection and Hohpe's ordering question at once: no two
   processes can both create the same claim.
   *Refined 2026-08-17:* three implementation constraints are load-bearing and are stated
   in Task 2 — `set -o noclobber` is set inside the register script itself and never
   assumed from the caller; creation is a `>` redirection and never `mktemp` + `mv`, which
   clobbers silently; and a failed redirection is confirmed as "the file already exists" by
   re-reading the path, so a missing or unwritable register directory reports an error
   instead of a holder.
4. **Ordering: claim first, tree second, ready third.** A timecard without a tree is
   reaped by liveness. A tree without a timecard is refused and reported by hygiene.
   A partially written claim is never authoritative — reconciliation is
   `reap`, never deadlock. (Hohpe.)
   *Amended 2026-08-17:* three cases the original wording left to invention are now
   specified. An empty or unparseable timecard is **dead**, never a holder, and is reaped
   (Task 2). A claim whose worktree creation then failed is released by the same guard
   that wrote it, in the same hook run (Task 4). A claim already held by **this** session
   is idempotent: the guard resumes it — completing the tree and marking it ready —
   instead of refusing, so one failed dispatch cannot brick a slug for the session's life.
   *Amended 2026-08-17, second pass (Stage 1's code review):* "reconciliation is reap"
   left the removal mechanics themselves unspecified, and a check-then-unlink reading of
   that sentence is a defect, not a simplification — stated plainly so a later reader does
   not "simplify" it back in. Several processes can judge the same card dead in the same
   instant; a scheme that renames the card to a tombstone and then unlinks it lets the
   second renamer take away the fresh card the first renamer's replacement just created,
   because naming a state is not the same as pinning the bytes judged. So removal pins the
   card's exact bytes first, with a hard link, and judges the dead verdict against those
   pinned bytes; the right to remove them is then won the same way a claim is won — an
   atomic exclusive create, of a token named after the pinned bytes' own digest — so a
   losing judge never touches the card path at all. Residual limit, stated rather than
   hidden: POSIX has no way to unlink a name conditionally on its contents, so the one
   window that remains is the instant between the digest check and the unlink, which
   requires the card's rightful owner not to have rewritten it in that instant. The claim's
   own election is unaffected by any of this — it is still decided by the exclusive create
   on the card path, never by this mechanism. See Task 2 and
   `hooks/agent-team-register-writer.sh`, `register_take_dead_card`.
   *Amended 2026-08-17, third pass (verified against the implementation; folded in here
   because it is the same removal-versus-rewrite hazard one function over):*
   `register_write_merged`
   no longer resurrects a card another process has just unlinked out from under it. Every
   rewrite hard-links the card to a private pin before reading it, exactly as a removal does;
   what is new is that, immediately before the final `mv` of the rewritten temp file onto the
   card path, the rewrite reads how many names that pin still has (`register_link_count`). A
   count of one means the card path is already gone — the rewrite is abandoned rather than
   `mv`ing a fresh copy back into existence, which is what an unconditional `mv` had done
   before: a heartbeat racing a release would wedge a slug until its session died, and one
   racing a writer release would leave a ghost holder for up to the TTL. Residual limit,
   stated rather than hidden, and the second of two places in this design portable shell
   cannot close (the first is the digest-check-then-unlink window above): the instant between
   reading the link count and the `mv` is not itself atomic, so a card unlinked in that
   instant is still resurrected. That window is microseconds wide; closing it would need an
   atomic-exchange or conditional-rename system call this project's shell primitives cannot
   reach. See `hooks/agent-team-register-lib.sh`, `register_write_merged` and
   `register_link_count`.
5. **`session_id` survives resume — verified.** All three live sessions examined span
   14→17 August in one file with one id each; no id is shared across files. A cleared or
   forked session mints a new id, so reaping is by process liveness, never by id match.
   *Amended 2026-08-17:* liveness and **membership** are now separate questions, and
   membership no longer rests on `session_id` alone. A timecard belongs to the agent whose
   hook is running when **either** its recorded session process matches (pid *and* process
   start time) **or** its `session` field equals the payload's `session_id`. Two reasons.
   First, a subagent's hook payload may or may not carry the parent session's id, and this
   plan must not rest on an unverified harness detail — the session process is the same
   for the orchestrator and every subagent it dispatches, because subagents run inside the
   one harness process, so the pid match carries the case where the ids differ. Second, a
   resumed session keeps its id and gets a new process, so the id match is what lets it
   adopt its own pre-resume claim (rewriting pid and start time, recorded as a fail-open).
   Neither test can match a foreign session: ids are unique per session and a live pid
   belongs to exactly one process.
   *Amended 2026-08-17, second pass (Stage 1's own acceptance run):* the paragraph above
   answers "who may ever resolve to this claim" — it does not answer "who may take over an
   *existing* claim outright," and those turned out to be different questions. Implemented
   literally, the twenty-way race case in the acceptance suite produced eighteen winners,
   not one: every racer in that race shares one session id and one long-lived harness
   process, so once the two-branch test above is applied on the **claim** path itself, every
   loser of the exclusive create still matches the winner's card by pid and is granted
   membership. Liveness (is the recorded process still running) and identity (whose claim
   is this) are separate questions on the claim path specifically, and the claim path uses
   **identity by session id alone**. Implemented: `register_claim` decides membership
   against an existing card with `register_claim_member`, which reads only the card's
   `session` field — never `pid`/`pid_start` — and a lost exclusive-create race is exit 3
   outright, with no membership test applied on that path at all. The pid stays a liveness
   fact on the claim path; it is never an identity fact there. The two-branch test above is
   otherwise unchanged and still governs `register_mine`, `register_session_claims`, and
   `register_release` — which is what the pid branch is actually *for*: a subagent whose
   hook payload carries a session id different from its parent's, and a resumed session
   adopting its own pre-resume claim by pid before its id has anywhere else to be read from.
   See Task 2, `register_claim` and `register_claim_member`.
6. **Cloud mutations are an explicit non-goal.** A workspace timecard is the wrong claim
   type for an IAM policy. Naming it out of scope beats an exemption inside the gate.
   (Hightower.)
7. **Every refusal carries its escape.** The message names the durable fact and the one
   command that resolves it, and the existing human-override marker
   (`WORKFORCE_OVERRIDE: lane-refusal`) is extended to workspace claims. False refusal
   is the failure mode with the worst history here; it gets an acceptance criterion of
   its own (Cockburn, Wiegers).
   *Amended 2026-08-17:* "a write is legal only inside the timecard's worktree" outlawed
   two writes the workflow itself depends on — the scribe's agent-memory writes at
   `~/.claude/projects/*/memory`, a path the lane configuration explicitly grants it
   (`hooks/agent-team-lanes.json:12`, documented at `README.md:107`), and any document
   write by a role that has no claim yet. The legality rule is therefore two-branch:
   **inside the session's claimed worktree, OR inside a lane this role owns whose path
   resolves outside every git working tree.** A lane that resolves *inside* a working tree
   (the architect's `plans`, the scribe's `docs`) is legal only inside the claimed tree, and
   the refusal names the one-line repair — the `CHANGE: <slug>` declaration — so the plan
   document lives with the change it plans. Task 7 writes that into the orchestrator: a
   task that will produce a commit declares its change at intake, before the first
   writing dispatch.
8. **Concurrency is tested with real processes before the feature is built** (Crispin),
   and the role documents are rewritten in the same change as the mechanism (Gregory).
   *Amended 2026-08-17:* "same change" is sharpened to "same **push**, and committed
   **after** it". Directive prose that lands in `origin/main` ahead of the guard it
   describes gives every new session an orchestrator told not to create worktrees and a
   guard that refuses builders without one — the workforce could not implement Stage 2
   with itself. See decision 9.
9. **Integration cadence: one push per stage, documents last within the stage.** *(New,
   2026-08-17, resolving the version window above.)* Stage 1 is pushed alone because it
   changes no rule and no instruction — it adds three libraries nothing calls yet. Stage 2's
   four tasks are committed separately and pushed **together**, with Task 7 (policy key,
   role documents, README rows, frontmatter assertions) as the last commit in the stage.
   Stage 3 is pushed after Stage 2. The rejected alternative was pushing every task as it
   lands: it produces at least two states of `origin/main` in which a new session cannot
   dispatch a builder at all. The cost of this cadence is that Stage 2's register-backed
   dispatch guard is not exercised by a fresh session until all four tasks are green; that
   is paid for by the acceptance suite, which runs the whole path against fixtures, and by
   AC-11, which is deliberately deferred to the first orchestrated task after landing.
10. **The workspace path and its ref are derived, never passed.** *(New, 2026-08-17,
    resolving "how does a builder learn its path".)* An exit-0/exit-2 hook cannot alter a
    dispatch prompt, so nothing is injected anywhere. Given a change slug, every
    participant computes the same two names: the worktree is
    `<project-root>/.claude/worktrees/<slug>` and its ref is `refs/heads/change/<slug>`.
    The timecard records both verbatim so a guard reads them rather than re-deriving them,
    and a slug is constrained to `[a-z0-9][a-z0-9._-]{0,63}` so it can never contain a
    path separator or `..`.
11. **Bash cannot be read/write-classified, so the Bash rule is per role.** *(New,
    2026-08-17.)* The verifier and the reviewer hold only `Read, Glob, Grep, Bash`; gating
    their Bash by working directory the way a builder's is gated would stop the verifier
    running the acceptance suite and the reviewer running the plan lint — breaking the very
    gates this change exists to strengthen. Roles are therefore split into four sets with
    four rules (the table in Task 5). "Denied writes outright" for the judges is enforced
    where it cannot be reasoned past — the tool layer, asserted in frontmatter — not by a
    guard that would have to classify shell commands.
12. **The register is the authority; the agent's own dispatch prompt is only a selector.**
    *(New, 2026-08-17, replacing "resolution is keyed on `session_id`, never from the
    transcript".)* Two transcript channels are not the same thing, and forbidding both
    made the plan's own parallelism promise unimplementable. Forbidden: scanning the
    **main-session** transcript for the most recent declaration — that is the 2026-08-04
    defect, where one session's oldest malformed declaration poisoned every later builder.
    Permitted: reading the **subagent's own** transcript, which contains exactly one
    dispatch prompt, already validated by the dispatch guard when it was issued. A
    transcript containing zero `Agent` tool_use blocks is a subagent's own by construction
    (no dispatched specialist holds the Agent tool), and that is the test the guard uses.
    So: the session's live claims come from the register; when there is more than one, the
    `CHANGE: <slug>` line in this agent's own dispatch prompt selects which one governs,
    and a selector that names no live claim is a refusal that lists every candidate.

## Open questions the tasks proceed on

- **Where an unattended warning goes.** Assumption: the guard log
  (`~/.claude/logs/agent-team-telemetry/guard-blocks.jsonl`) plus a line in the closeout
  receipt, since that is the one surface the human always reads. Revisit if closeout
  noise becomes the complaint.
- **Whether the orchestrator loses Bash in this change or the next.** Assumption: not in
  this change. The register gate (Stage 2, Task 5) makes its shell harmless first;
  removing the tool is a separate, reviewable step so a regression in the gate does not
  blind the orchestrator at the same moment.
- **Whether a subagent's hook payload carries the parent session's id.** Not verified, and
  deliberately not depended on: decision 5's two-branch membership test holds either way.
  Task 4 records which branch actually fired in the guard log (`detail` field
  `membership=pid` or `membership=session-id`), so the first orchestrated task after
  landing answers the question from evidence.

## Executing this plan under the old rules

This is the one plan whose builders run under the guards it is changing, so the sequence
is load-bearing and is stated rather than left to inference.

- **This session's own dispatches follow the OLD contract, from first to last.** The
  installed hooks are pinned to the build resolved at this session's first hook call
  (`hooks/agent-team-pin.sh:61`–`:99`), so nothing this task commits changes this
  session's enforcement. Every builder dispatch this session issues therefore still needs
  a worktree the orchestrator created and a `WORKTREE: <path>` line, exactly as
  `agent-team-dispatch-guard.sh:328`–`:381` requires today. Reading the new prose in this
  plan is not permission to stop doing that.
- **This session must not run `install.sh` and must not re-run `bin/agent-workforce`.**
  Hook pinning would protect this session's guards, but `agents/*.md` is copied flat and
  is not pinned, so an install mid-session hands the *next* builder new instructions while
  the pinned guard still enforces the old rules — BLOCK 4's trap, inside one session.
- **The last stage boundary at which this session can still safely dispatch a builder is
  the end of Stage 3** — that is, all of them — *because* nothing is installed
  mid-session. The boundary that actually matters is not a stage: it is the install. The
  install is the human's step, after Stage 3 reaches `origin/main`, and the first session
  launched after it is the first session running the new mechanism.
- **The new mechanism is therefore not proved end-to-end by this task.** That proof is
  AC-11, deferred by construction to the first orchestrated task after landing and
  verified in that task's closeout.

## The acceptance suite (authored by the test-author, red before any builder)

The bar for this plan is one separately-authored file,
`tests/acceptance/test_workspace_isolation.sh`, written from this plan by the test-author,
committed red, and read-only to every builder thereafter (the worktree guard enforces that
once `tests/acceptance/` exists). It prints `PASS [<label>]` / `FAIL [<label>]: <why>` per
case and a trailing `passed=<n> failed=<n>` summary. The acceptance criteria count these
exact labels; the labels are the contract between this plan and that suite.

Turned green by Stage 1:

- `exactly one of twenty claimants wins`
- `claim survives the hook process that created it`
- `claim is reaped only after the session process exits`
- `a recycled pid with a different start time is reaped`
- `an empty timecard is reaped, not honoured as a holder`
- `a missing register directory is an error, not a holder`
- `two projects may hold the same slug at once`
- `installer touchpoints cover the new hook files`

Turned green by Stage 2:

- `re-claim after reap adopts the surviving worktree`
- `a retry after a failed tree creation re-claims the same slug`
- `a retry after a crash before ready completes the claim`
- `a second live session is refused and the holder is named`
- `two live writers on one change are refused`
- `a stale writer slot is releasable`
- `shared-checkout write refused: builder`
- `shared-checkout write refused: test-author`
- `shared-checkout write refused: architect`
- `shared-checkout write refused: scribe`
- `shared-checkout write refused: executor`
- `shared-checkout write refused: deployer`
- `shared-checkout write refused: verifier`
- `shared-checkout write refused: reviewer`
- `shared-checkout write refused: debugger`
- `shared-checkout write refused: ops`
- `scribe memory write with no claim is allowed`
- `architect plan write inside the claimed tree is allowed`
- `verifier runs the acceptance suite from the shared checkout`
- `reviewer runs the plan lint from the shared checkout`
- `two live claims with no selector is a refusal naming both`
- `a selector naming no live claim is a refusal naming both`
- `a dispatch declaring PARALLEL_SAFE may not write`

Turned green by Stage 3:

- `a bare Stop with a live claim integrates nothing`
- `a completion claim with no change disposition is blocked`
- `an integrated claim survives closeout only as a verified fact`
- `hygiene lists a held claim and flags an unclaimed tree`

---

## Stage 1 — Foundation

Integrates alone and safely: it adds three sourced libraries and one config file that no
guard calls yet, and changes no rule and no instruction.

### Task 1: the concurrency test harness

**Files.** Create `tests/lib/concurrency.sh`, `tests/test_register_concurrency.sh`.

**Interfaces produced.**
- `spawn_claimants <n> <register-dir> <project-root> <slug>` — starts `n` real background
  processes, each running `bash hooks/agent-team-register.sh claim <project-root> <slug>
  <session-id>` with `AGENT_TEAM_REGISTER_DIR=<register-dir>`, each writing its exit
  status to `<register-dir>/../out/<i>.rc`, and waits for all of them.
- `assert_exactly_one_winner <out-dir>` — prints
  `PASS [exactly one of twenty claimants wins]` when exactly one `.rc` file holds `0` and
  every other holds `3`; otherwise prints `FAIL [...]: winners=<w> refusals=<r>
  other=<list>`.

**Steps.**
1. [ ] Write `tests/lib/concurrency.sh` with the two functions above. Each claimant is a
   separate `bash` process started with `&`, and all of them are started before any is
   waited on, so the race is real rather than sequential.
2. [ ] Write `tests/test_register_concurrency.sh`: build a temporary project fixture
   (`git init -q -b main`, one commit), point `AGENT_TEAM_REGISTER_DIR` at a temporary
   directory inside the fixture, call `spawn_claimants 20 ...`, then
   `assert_exactly_one_winner`.
3. [ ] Run `bash tests/test_register_concurrency.sh` — expect failure with
   `hooks/agent-team-register.sh: No such file or directory` on every claimant and
   `FAIL [exactly one of twenty claimants wins]: winners=0`.
4. [ ] Leave it red; Task 2 turns it green. Commit the harness alone:
   `git commit -am "test(register): a real multi-process race harness, red until the register exists"`

### Task 2: the register primitive

**Files.** Create `hooks/agent-team-register.sh`, `hooks/agent-team-register.json`,
`hooks/agent-team-register-lib.sh`, and `hooks/agent-team-register-writer.sh`.
*Amended 2026-08-17, Stage 1's code review:* the split is three-way, and the line between
the last two files is drawn by contention, not only by size. `agent-team-register-lib.sh`
carries the **computed** facts — derived names, session-process resolution, liveness,
membership, card-validity, and safe rewrites — anything a reader can decide alone.
`agent-team-register-writer.sh` carries the **contended** facts — the exclusive take every
removal goes through, and the writer slot built on it — anything that pits two processes
against each other and can therefore never be settled by a read followed by a write; the
original design read the card's `writer` field and then wrote it, and that read-then-write
is the two-simultaneous-writers defect the repair fixed (decision 1). With every function
documented, the register alone would run past 400 lines undivided. `agent-team-register.sh`
sources both siblings from its own directory — the same precedent `agent-team-lane-guard.sh`
already sets by sourcing `agent-team-lane-paths.sh` — and fails hard with a repair line
(`Re-run: bash install.sh`) when either sibling is missing beside it, exactly as that
precedent does. Sourcing `agent-team-register.sh` still defines every function this task
names; nothing that sources the register changes because of the split. Modify `install.sh`
(the five per-file touchpoints — `HOOK_FILES` at `:127`, the pre-install backup block at
`:556`–`:586`, the `restore()` case list at `:659`–`:663`, the `cleanup_fresh` removals at
`:718`–`:722`, and the forward copy at `:763`–`:767` — for each of these four new files;
plus three `bash -n` lines beside the checks at `:190`–`:199`, one each for
`agent-team-register.sh`, `agent-team-register-lib.sh`, and `agent-team-register-writer.sh`
— `agent-team-register.json` gets no `bash -n` line, being JSON rather than shell).
Test `tests/test_register.sh` (new, the register's DECISIONS — who may claim, release, and
write), `tests/test_register_lifecycle.sh` (new, a card's LIFETIME — naming, liveness, reap,
crash debris), `tests/test_register_races.sh` (new, the RACE tier — real multi-process
contention for the writer slot and the digest-checked take, sequential by design so nothing
competes for the cores the interleaving needs), `tests/lib/register-fixture.sh` (new, the
shared fixture and case-runner the three files above all source — its own concurrent-case
runner is what keeps the unit tier itself fast: `tests/test_register.sh` and
`tests/test_register_lifecycle.sh` each run their cases in the background against their own
per-case fixture directory, so the whole tier finishes in about the time its slowest single
case takes, not the sum of all of them), `tests/test_register_concurrency.sh` (from Task 1,
the twenty-claimant race on the claim path itself), `tests/test_install_touchpoints.sh`
(existing, must stay green).

**Interfaces produced.** A sourced library that also runs as a CLI (defined across
`agent-team-register.sh` and the sibling libraries it sources; sourcing the former still
defines every function below). Sourcing defines functions only; executing dispatches
subcommands (`claim`, `ready`, `holder`, `mine`, `release`, `reap`, `writer-acquire`,
`writer-release`, `heartbeat`, `session-claims`, `card-path`, `worktree-path`) whose names
and argument order match the functions below one-for-one. Two internal helpers carry no CLI
subcommand of their own and are named here so a later reader does not mistake them for
undocumented surface: `register_writer_take_matching <slot-file> <json-field>
<wanted-value>` (in the writer file) pins the slot file, takes it only when the pinned bytes'
named field equals `<wanted-value>`, and is what both `register_writer_release` and
`register_reap` use to remove a slot only when it still names the session or slot they judged
it against; `register_link_count <path>` (in the register library) prints how many names a
path still has (`stat -f %l` or `stat -c %h`), which `register_write_merged` reads on the pin
immediately before its final move to tell "the card is gone" from "another process is merely
also pinning it."

- `register_config_int <key> <default>` → the integer from
  `hooks/agent-team-register.json` beside this script, or the default when the file is
  missing or unreadable. Config: `{"schema":1,"writer_ttl_seconds":900,
  "claim_stale_warn_seconds":86400}`.
- `register_root` → `${AGENT_TEAM_REGISTER_DIR:-$HOME/.claude/state/agent-workforce-register}`.
- `register_project_root <dir>` → the **main** checkout for `<dir>`: `git -C <dir>
  rev-parse --show-toplevel`, and when that top level is itself a linked worktree (its
  `.git` is a file whose first line matches `^gitdir: .*/\.git/worktrees/[^/]+$`), the
  prefix before `/.git/worktrees/`. Empty output plus exit 5 when `<dir>` is in no
  repository.
- `register_project_key <project-root>` → the first 12 hex characters of the SHA-256 of
  the canonical project root path, using `shasum -a 256` or `sha256sum`, whichever exists;
  exit 5 when neither does. This is what keeps two unrelated projects both claiming
  `fix-typo` from colliding.
- `register_card_path <project-root> <slug>` →
  `<register-root>/<project-key>/<slug>.json`.
- `register_worktree_path <project-root> <slug>` →
  `<project-root>/.claude/worktrees/<slug>`.
- `register_ref_name <slug>` → `change/<slug>` (the full ref is
  `refs/heads/change/<slug>`).
- `register_valid_slug <slug>` → exit 0 when the slug matches
  `^[a-z0-9][a-z0-9._-]{0,63}$` and contains no `..`; else exit 6.
- `register_session_process` → prints `<pid>` and `<start-string>` on one line separated
  by a tab: the **session's long-lived harness process**, found by walking ancestry
  upward from `$PPID`. At each step, `ps -p <pid> -o ppid=` gives the parent and
  `ps -p <pid> -o comm=` gives the command; the basename of the command, with any leading
  `-` stripped, is compared against the shell set `sh bash dash zsh ksh csh tcsh fish env
  timeout nice sudo ps`. The first ancestor **not** in that set is the answer; if the walk
  reaches pid 1 without finding one, the last ancestor before pid 1 is the answer; if
  there is no ancestor at all, exit 4. The start string is `ps -p <pid> -o lstart=`
  verbatim (it contains spaces, so it is read by its own `ps` call and stored as a
  string). This is the field BLOCK 1 turns on: the process the hook runs in exits seconds
  after the dispatch is allowed, and recording it would make every claim look dead.
- `register_alive <pid> <start-string>` → exit 0 when `kill -0 <pid>` succeeds **and**
  `ps -p <pid> -o lstart=` still equals `<start-string>`; else exit 1. Both halves are
  required: without the start string a recycled pid reports a stale claim as live and
  holds a slug indefinitely. Noted limit, single-user machine: `kill -0` also fails with
  EPERM for a live process owned by another user, which would read as dead — acceptable
  here, and the reason the start-time comparison (which needs no permission) is the
  second half rather than the only half.
- `register_claim <project-root> <slug> <session-id>` → exit 0 and print the **card path**
  when the claim is taken or already held by this same session (idempotent) — `claim`
  always prints a path on success, never the card's JSON; exit 3 and print the holder's
  JSON when a **live** foreign session holds it, including when this call lost an
  exclusive-create race; exit 4/5/6 per above. Behaviour, in order: validate the slug;
  resolve the session process; reap this one card if its recorded process is dead or its
  content is empty or unparseable; if a card still exists, decide membership by **session
  id alone** (`register_claim_member`, decision 5's second-pass amendment below) — a member
  prints the existing card's path and returns exit 0 (idempotent), a non-member prints the
  card's JSON and returns exit 3, with **no** pid-branch test applied on this path; otherwise
  attempt the exclusive create — on success, print the new card's path and return exit 0;
  on a lost race (the path now exists because another claimant won it first), print that
  card's JSON and return exit 3, again with no membership test on this path at all.
- `register_claim_member <card> <session-id>` → exit 0 when the card is live JSON and its
  `session` field equals `<session-id>`. This is the **only** membership test the claim
  path applies; it never reads `pid`/`pid_start`. That comparison is decision 5's other
  branch, reserved for `register_mine`, `register_session_claims`, and `register_release`
  below, where the pid branch is what lets a subagent whose payload session id differs from
  its parent's, or a resumed session, resolve a claim its own process actually holds.
- `register_resolve_card <project-root> <slug>` — **internal**, not a CLI subcommand:
  prints the path of an existing card, or exit 1 (no such card) / 5 (project or register
  unresolvable) / 6 (bad slug). Every function below that operates on an already-claimed
  card (`register_ready`, `register_holder`, `register_mine`, `register_release`,
  `register_writer_acquire`, `register_writer_release`, `register_heartbeat`) resolves the
  card path through this helper first.
- `register_ready <project-root> <slug>` → sets `state` to `ready`.
- `register_holder <project-root> <slug>` → prints the card's JSON, or nothing and exit 1.
- `register_mine <project-root> <slug> <session-id>` → exit 0 when the card exists and
  passes decision 5's **full two-branch** membership test (pid match or session-id match —
  not the claim path's session-id-only rule above); prints `pid` or `session-id` naming
  which branch matched.
- `register_session_claims <project-root> <session-id>` → one line per live card in this
  project that this session is a member of: `<slug>\t<worktree>\t<state>`. Membership here
  is again decision 5's full two-branch test, matching `register_mine`.
- `register_release <project-root> <slug> [session-id]` → deletes the card **only** when
  membership holds against the given `[session-id]` (decision 5's full two-branch test, pid
  or session id) or the card's process is dead; exit 3 without deleting otherwise.
  *Amended 2026-08-17, Stage 1's code review:* the third argument is **load-bearing**, not
  optional in effect. The original implementation defaulted a missing `[session-id]` to the
  card's own `session` field, which made the session-id branch of the membership test
  compare the card against itself — always true — and let any process release any live
  claim regardless of who held it. An omitted `[session-id]` now resolves membership by the
  **pid branch only**; a caller whose payload session id differs from its own process (Task
  4's dispatch guard releasing a card it just wrote; Task 8's closeout, via
  `workspace_integrate`) must pass that id explicitly or the pid branch is all it gets.
- `register_writer_acquire <project-root> <slug> <slot>` → creates the writer slot file
  `<register-root>/<project-key>/writers/<slug>.json` (`{"slot":<slot>,"session":<session-id>,
  "heartbeat":<epoch>}`) under `noclobber` — the same atomic exclusive create the claim
  itself uses — then mirrors the result into the card's `.writer` field; exits 0 when the
  slot file does not exist, when it already names `<slot>`, when its heartbeat is older than
  `writer_ttl_seconds`, or when the card's session process is dead (a stale slot is
  displaced by the same take-and-re-judge sequence a dead card goes through, never by an
  unconditional unlink). Otherwise exit 3, printing the holding slot and the age in seconds.
  A TTL displacement is recorded as a fail-open in the guard log by the caller.
- `register_writer_teardown <project-dir> <slug>` → removes the slot file
  **unconditionally**, whoever holds it, and nulls the card's `.writer` mirror. This is a
  different act from a slot holder releasing its own slot: it is only for a caller that has
  already established the claim is its own and is tearing the whole claim down, so there is
  no change left for any writer to hold a slot in. `workspace_integrate` (Task 3) uses this
  in place of `register_writer_release`, because at that point membership on the claim is
  already established and the writer slot — whoever holds it — comes down with the claim.
  *Amended 2026-08-17, Stage 1's code review:* the slot was originally the card's own
  `writer` field, set by reading the existing value and writing the new one — not atomic,
  so two guards racing for the same slot both read it empty and both were granted,
  reproduced at five winners out of eight racers. The slot is now decided by the file's own
  existence; the card's `.writer` field is written after and is a **mirror only**, read by
  the operator view and the staleness heartbeat, never by this function.
- `register_writer_release <project-dir> <slug> <slot>` → the slot the caller holds is a
  **required** third argument, not an optional one: it pins the slot file's exact bytes
  (the same hard-link-then-digest take every removal in the register goes through), compares
  the slot recorded in those pinned bytes against `<slot>`, and removes the slot file only
  when they match — never an unconditional unlink. Exit 2 when `<slot>` is omitted, before
  anything is touched; exit 3 when the slot named is not the recorded holder, naming the
  actual holder; exit 0 on release, after which the card's `.writer` mirror is nulled — and
  only while it still names this slot. *Amended 2026-08-17, Stage 1's code review, third
  pass:* the two-argument form (unlink unconditionally) was the same defect as the stealable
  claim release one level down (decision 1) — a release with no ownership check let one agent
  drop another's exclusion, after which a third agent was granted a slot two agents still
  believed they held. See `register_writer_take_matching` and `register_writer_unrecord` in
  `hooks/agent-team-register-writer.sh`.
- `register_heartbeat <project-root> <slug> [slot]` → refreshes the card's `heartbeat`,
  and the writer entry's mirror too when `[slot]` is given and matches. *Amended
  2026-08-17, Stage 1's code review:* since the writer slot moved to its own file, this
  also refreshes that file's own `heartbeat` when `[slot]` matches it — a heartbeat keeps
  the slot fresh through either record, card mirror and slot file alike.
- `register_reap <project-root>` → for every card in the project's directory, remove it
  when its content is empty or unparseable, or when `register_alive` fails for its
  recorded process; print one `reaped <slug> <reason>` line per removal, and take the
  removed card's writer slot file with it. Never removes a card whose process is live,
  whatever its age. *Amended 2026-08-17, Stage 1's code review:* `register_reap` now also
  sweeps crash debris no card glob would ever match — an interrupted rewrite's temp file, a
  take's pin, a displacer's pin, an abandoned take token — left behind by a process that
  died mid-write; each swept file prints its own `swept <name> <reason>` line, in the same
  stream as, but never in place of, the `reaped <slug> <reason>` lines. Anything parsing
  reap output still matches on the `reaped ` prefix; a `swept` line is new output, not a
  changed one.

Timecard schema, version 1:

```json
{"v":1,"slug":"<slug>","project":"<absolute main checkout>","project_key":"<12 hex>",
 "session":"<session id>","pid":<session process pid>,"pid_start":"<ps lstart string>",
 "worktree":"<absolute path>","ref":"refs/heads/change/<slug>",
 "base_ref":"<ref the tree was created from>","base_sha":"<40 hex>",
 "state":"claiming","opened":"<ISO-8601 UTC>","heartbeat":<epoch seconds>,"writer":null}
```

*Amended 2026-08-17, Stage 1's code review:* the `writer` field above is a **mirror**, not
the decision. Occupancy of the writer slot is decided by the existence of a separate file,
`<register-root>/<project-key>/writers/<slug>.json`; this field is written after that file
and exists so the operator view (Task 9) and the staleness heartbeat (`register_heartbeat`)
have something to read without opening a second file. A reader that finds `writer:null` here
while the slot file exists has read a stale mirror, not an authoritative answer — nothing in
this plan reads this field to decide who may write.

Creation and rewrite rules, all three from decision 3:

- Creation is `( set -o noclobber; printf '%s\n' "$json" > "$card" )`. The `set -o
  noclobber` is inside that subshell in this script — never assumed from the caller — and
  the redirection is `>`, which Bash implements with `O_CREAT|O_EXCL` and which is atomic
  on APFS. `mktemp` + `mv` is forbidden for creation: it clobbers silently and destroys
  the exclusion this whole design rests on.
- A failed redirection is **not** evidence of a holder. Re-read the path: when the file
  exists, the claim is held; when it does not, the register directory is missing or
  unwritable, which is exit 5 with the repair (`mkdir -p` on the register root) and never
  a holder.
- Every rewrite (`ready`, `heartbeat`, writer changes) reads the existing object, merges
  the changed fields with `jq`, writes a temp file in the same directory and `mv`s it over
  the card, so unknown fields written by a newer guard survive an older pinned guard.

**Steps.**
1. [ ] Write `tests/test_register.sh` covering, with these exact case labels: `claim
   succeeds and prints the card path`; `a second claim by a foreign live session exits 3
   and names the holder`; `a second claim by the same session is idempotent`; `claim
   survives the hook process that created it`; `claim is reaped only after the session
   process exits`; `a recycled pid with a different start time is reaped`; `an empty
   timecard is reaped, not honoured as a holder`; `a missing register directory is an
   error, not a holder`; `two projects may hold the same slug at once`; `an unknown field
   survives a heartbeat`; `a malformed slug is refused`; `writer slot is exclusive`; `a
   stale writer slot is releasable`.
   The liveness cases use a real process tree rather than a mock: a long-lived
   non-shell parent started as `python3 -c "import subprocess,sys,time;
   subprocess.run(sys.argv[1:]); time.sleep(300)" bash -c '<claim command>'` — the claim
   runs in a short-lived `bash` child whose first non-shell ancestor is that `python3`
   process. Assert the card still resolves as live after the `bash` child has exited, then
   `kill` the `python3` process and assert `register_reap` removes it. The recycled-pid
   case rewrites a card's `pid` to the test's own live pid while leaving `pid_start` as a
   fabricated older string, and asserts the card is reaped.
2. [ ] Run `bash tests/test_register.sh` and `bash tests/test_register_concurrency.sh` —
   expect both to fail with `agent-team-register.sh` missing.
3. [ ] Implement `hooks/agent-team-register.sh`, `hooks/agent-team-register-lib.sh`, and
   `hooks/agent-team-register.json`.
4. [ ] Wire the three new files through all five installer touchpoints and add the two
   `bash -n` lines (one for `agent-team-register.sh`, one for `agent-team-register-lib.sh`).
   Run `bash tests/test_install_touchpoints.sh` — expect
   `install-touchpoint tests: PASS=<n> FAIL=0`.
5. [ ] Run all three — expect pass, including `PASS [exactly one of twenty claimants
   wins]`.
6. [ ] `git commit -am "feat(register): a timecard per change, exclusive by filesystem create"`

### Task 3: the workspace primitive

**Files.** Create `hooks/agent-team-workspace.sh`. Modify `install.sh` (the same five
touchpoints plus its `bash -n` line). Test `tests/test_workspace.sh` (new),
`tests/test_install_touchpoints.sh`.

**Interfaces produced.** A sourced library that also runs as a CLI (`ensure`, `integrate`,
`remove`). It sources `agent-team-register.sh` from its own directory. It is the **only**
component in this plan that runs a mutating git command, and no agent invokes `ensure`
directly — the dispatch guard does.

- `workspace_ensure <project-root> <slug> <base-ref>` → prints the worktree path, exit 0.
  This is BLOCK 5's adoption rule, in order:
  1. Refuse (exit 7) unless `git -C <project-root> check-ignore -q .claude/worktrees`
     succeeds, naming the `.gitignore` line to add — an un-ignored worktree directory
     turns every change into dirt in the shared checkout.
  2. Derive `path` and `ref` per decision 10.
  3. Read `git -C <project-root> worktree list --porcelain`. **When `path` is listed but
     its directory is gone from disk**, run `git -C <project-root> worktree prune` once and
     re-read the list — a registration whose tree has already vanished (removed by hand, or
     by a completed integration) is stale, and the step below must not read it as a tree
     still there to adopt.
  4. When `path` is listed at `refs/heads/change/<slug>` **and its directory still exists**,
     **adopt it**: print the path and exit 0 without touching git. This is what makes a
     re-claim after a reap succeed against the tree the dead session left behind.
  5. When `path` is listed at a different ref, exit 7 naming both refs and the repair
     (`git -C <project-root> worktree remove <path>`).
  6. When `path` exists on disk but is not listed, run `git -C <project-root> worktree
     prune` once and re-read the list; if it is still unlisted and still present, exit 7
     naming the path and the repair.
  7. When the ref `refs/heads/change/<slug>` already exists (`git -C <project-root>
     show-ref --verify --quiet refs/heads/change/<slug>`), attach the tree to it:
     `git -C <project-root> worktree add "<path>" "change/<slug>"`. This is also the path
     step 3's prune falls through to once the tree is confirmed gone: the ref a vanished
     tree left behind is still there, so committed work on it is never stranded.
  8. Otherwise create both: `git -C <project-root> worktree add "<path>" -b
     "change/<slug>" "<base-ref>"`. Exit 7 on failure, printing git's own stderr.
- `workspace_integrate <project-root> <slug> <integration-ref> [session-id]` → exit 0 only
  after all of it succeeded, and exit 8 with the reason otherwise. In order: the card
  exists and this session is a member (`register_mine`, decision 5's full two-branch test)
  — with no fourth argument, membership can only be established by the pid branch, since
  there is then no session id to compare against; a caller holding a payload session id
  different from its own process passes it as the fourth argument so the session-id branch
  has something to test (Task 8: this is exactly the executor's case); `git -C <worktree>
  status --porcelain` is empty (else exit 8 naming
  the dirty paths); `git -C <project-root> symbolic-ref --short HEAD` equals
  `<integration-ref>` (else exit 8); `git -C <project-root> status --porcelain` is empty
  (else exit 8); then `git -C <project-root> merge --no-ff --no-edit "change/<slug>"`;
  then `git -C <project-root> worktree remove "<path>"`; then `git -C <project-root>
  update-ref -d "refs/heads/change/<slug>"`; then `register_writer_teardown` — the
  claim-scoped teardown, not `register_writer_release`, because membership on the claim is
  already established at this point and the whole claim is coming down, so the writer slot
  goes with it whoever holds it — and `register_release`. A conflicted merge exits 8 after
  `git -C <project-root> merge --abort`, leaving the tree, the ref, and the timecard exactly
  as they were.
- `workspace_remove <project-root> <slug> [session-id]` → validates the slug at entry
  (exit 6 for a malformed one, before anything is touched); when a card exists, checks
  membership against `[session-id]` **before** destroying anything and exits 8, naming the
  holding session, for a foreign claim; removes the tree and deletes the ref **only** when
  `git -C <project-root> merge-base --is-ancestor "change/<slug>" HEAD` succeeds, exit 8
  naming the unmerged commits otherwise; then releases the card and returns the register's
  own status when the release fails, rather than reporting success on a failed release — a
  claim that survives the workspace it named is a slug held by nothing, and this function no
  longer hides that. *Amended 2026-08-17, Stage 1's code review:* the original wording
  implied check-then-destroy-then-release-and-ignore-the-result; the membership check now
  gates entry, and the final `register_release` call's exit code is returned to the caller
  (except exit 1, no such card, which is treated as already-released and returns 0).

**Steps.**
1. [ ] Write `tests/test_workspace.sh` with these case labels: `ensure creates the derived
   worktree at the derived ref`; `ensure adopts an existing registered tree`; `ensure
   refuses a tree registered at another ref`; `ensure prunes a stale registration and
   retries`; `ensure attaches to an existing ref whose tree was removed`; `ensure refuses
   when the worktree directory is not gitignored`; `integrate refuses a dirty change
   tree`; `integrate refuses when HEAD is not the integration ref`; `integrate merges,
   removes the tree, deletes the ref, and releases the card`; `a conflicted merge aborts
   and leaves the claim intact`; `remove refuses an unmerged change`.
2. [ ] Run `bash tests/test_workspace.sh` — expect failure, `agent-team-workspace.sh`
   missing.
3. [ ] Implement `hooks/agent-team-workspace.sh`; wire it through the five installer
   touchpoints and add its `bash -n` line.
4. [ ] Run `bash tests/test_workspace.sh` and `bash tests/test_install_touchpoints.sh` —
   expect pass and `FAIL=0`.
5. [ ] `git commit -am "feat(workspace): create, adopt, and integrate a change's worktree in one place"`

**Stage 1 integration.** Run `tests/test_register.sh`,
`tests/test_register_concurrency.sh`, `tests/test_workspace.sh`,
`tests/test_install_touchpoints.sh`, and `tests/test_hook_pin.sh`; each must end
`failed=0` or `FAIL=0`. Then push Stage 1's three commits to `origin/main`. Nothing
installed by them is called by any guard, and no instruction has changed, so a session
launched between Stage 1 and Stage 2 behaves exactly as it does today.

## Stage 2 — Administration by declaration

**One push for the whole stage** (decision 9), with Task 7 committed last. No individual
task in this stage is pushed on its own.

### Task 4: the dispatch guard claims, creates, adopts, and resumes

**Files.** Modify `hooks/agent-team-dispatch-guard.sh`: replace the workspace-isolation
block at `:286`–`:470` (which today comprises the `GIT_SERIALIZED_ROLES` scan at
`:289`–`:295`, `normalize_worktree` at `:301`–`:303`, the `WORKTREE:` shape and existence
checks at `:305`–`:397`, and the transcript collision scan at `:399`–`:469`); add the
constants beside `:21`–`:25`. Test `tests/test_dispatch_guard.sh`.

**Interfaces consumed.** `register_claim`, `register_holder`, `register_mine`,
`register_ready`, `register_release`, `register_reap`, `register_writer_acquire`,
`register_project_root`, `register_valid_slug`, `workspace_ensure`.

**Interfaces produced.**
- `readonly CHANGE_MARKER_PREFIX="CHANGE:"` and
  `readonly PARALLEL_SAFE_MARKER="PARALLEL_SAFE: this dispatch writes nothing"`.
- `readonly CHANGE_REQUIRED_ROLES="builder test-author executor deployer"` — the roles a
  dispatch must declare a change for. The debugger and ops **may** declare one and it is
  honoured when present, because their Bash rule (Task 5) refuses git mutation outside a
  claimed tree; a diagnosis that will commit declares its change like anything else.
- The retired `WORKTREE:` marker is refused, not ignored: a dispatch carrying a
  `WORKTREE:` line is blocked with a message naming `CHANGE: <slug>` as its replacement,
  so a stale habit produces one clear correction instead of a silently unenforced line.
- The old `PARALLEL_SAFE: no git mutation in this dispatch` literal is likewise refused
  with a message naming the new literal, because the meaning changed: it now asserts the
  dispatch **writes nothing at all**, and Task 5 verifies that rather than trusting it.
- A dispatch with neither a `CHANGE:` line nor the `PARALLEL_SAFE` line, in a role that
  requires one, is refused. The old implicit serialisation of undeclared targets
  (`:459`–`:467`) is retired along with the transcript collision scan: two live writers
  are now decided by the register's writer slot, which is a durable fact, rather than by
  reading the transcript for unresolved dispatches.

Behaviour for a declared change, in order: resolve the project root from `.cwd`;
`register_reap` the project; `register_claim`; on exit 3, refuse naming the holding
session, its slug, its worktree, how long it has been held, and the two escapes (wait, or
the human's `WORKFORCE_OVERRIDE: lane-refusal | <slug>` line); on exit 0, call
`workspace_ensure`; on `workspace_ensure` failure, call
`register_release <project-root> <slug> <session-id>` — passing the payload's own session
id explicitly, since that third argument is now load-bearing and an omitted one resolves
membership by the pid branch alone (2026-08-17, Stage 1's code review) — for the card this
hook just wrote and refuse with git's own message — SHOULD 10's window A, so a failed
tree creation never leaves a `claiming` card behind a live pid; on success,
`register_ready` and `register_writer_acquire "<role>#<n>"`, where `<n>` is the count of
prior dispatches of this role for this slug in the payload's transcript, so two builders
repairing one change hold distinct slot names. Should this guard ever release a writer
slot (`register_writer_release`), the third argument — the exact slot string it acquired
with — is required, not optional (2026-08-17, Stage 1's code review, third pass): a caller
that omits it or reconstructs the slot name differently is refused rather than allowed to
release a slot it does not name correctly.

Same-session resumption (SHOULD 10, both windows): when `register_claim` returns exit 0
against an **existing** card this session is a member of, the guard does not refuse. A
card in `state: claiming` is resumed — `workspace_ensure` then `register_ready` — and a
card in `state: ready` is verified by `workspace_ensure`'s adoption path. One failed
dispatch therefore cannot brick a slug for the session's life.

**Steps.**
1. [ ] Add cases to `tests/test_dispatch_guard.sh` with these labels: `a builder dispatch
   declaring a new change claims it and creates the tree`; `the same slug from a foreign
   live session is refused with the holder named`; `re-claim after reap adopts the
   surviving worktree`; `a retry after a failed tree creation re-claims the same slug`; `a
   retry after a crash before ready completes the claim`; `two live writers on one change
   are refused`; `a second writer slot after the TTL is granted and logged as a
   fail-open`; `a WORKTREE: line is refused and names CHANGE:`; `the retired PARALLEL_SAFE
   literal is refused and names the new one`; `a builder with neither CHANGE: nor
   PARALLEL_SAFE is refused`; `an executor dispatch declaring a change claims it`; `a
   malformed slug is refused before anything is created`.
   The reap case is the one BLOCK 5 turns on: claim, kill the holder process, `register_reap`,
   then re-claim the same slug and assert exit 0 **and** that
   `git -C <project> worktree list --porcelain` still lists the same path at the same ref.
   Every case exports `AGENT_TEAM_REGISTER_DIR` into its own fixture.
2. [ ] Run `bash tests/test_dispatch_guard.sh` — expect the new cases to fail and every
   pre-existing case to pass.
3. [ ] Implement, deleting the `WORKTREE:` shape and existence checks and the transcript
   collision scan that the register replaces.
4. [ ] Run `bash tests/test_dispatch_guard.sh` — expect pass.
5. [ ] `git commit -am "feat(dispatch): a change declaration claims its workspace and the hook builds it"`

### Task 5: the worktree guard resolves and gates from the register

**Files.** Modify `hooks/agent-team-worktree-guard.sh`: replace `declared_worktree`
(`:203`–`:264`) and `live_declaration_count` (`:266`–`:294`) and their call sites
(`:296`–`:325`); add the legality branch and the per-role Bash rule to the PreToolUse
section (`:335`–`:407`). Modify `tests/test_worktree_guard.sh` — the whole
resolution section at `:193`–`:280` is rewritten, not one case (see below). Test
`tests/test_worktree_guard.sh`.

**Interfaces consumed.** `register_session_claims`, `register_holder`, `register_mine`,
`register_heartbeat`, `register_project_root`, and `lane_role_spec` / `lane_pattern` /
`lane_covers` from `hooks/agent-team-lane-paths.sh` (already sourced by two guards; this
becomes the third reader of that one rule).

**Interfaces produced.**
- `resolve_change <role>` → prints `<slug>\t<worktree>` for the change that governs this
  agent, or one of the words `none` or `ambiguous`. Per decision 12: the candidate set is
  `register_session_claims`; one candidate resolves; more than one is narrowed by
  `own_dispatch_change`; a selector naming no candidate, or no selector with more than one
  candidate, yields `ambiguous`.
- `own_dispatch_change` → the `CHANGE:` slug from **this agent's own** dispatch prompt,
  read only when the transcript contains zero `Agent` tool_use blocks — the structural
  test that it is a subagent's own transcript. When `Agent` blocks are present the
  transcript is a main session's and this function returns nothing: the recency scan that
  poisoned six dispatches on 2026-08-04 does not come back.
- `own_dispatch_parallel_safe` → exit 0 when that same own-transcript prompt carries the
  `PARALLEL_SAFE` marker. Known limit, stated: when the guard is handed a main-session
  transcript instead of the subagent's own, a `PARALLEL_SAFE` assertion cannot be checked
  and the write is judged by the timecard rule alone. That bounds the failure to a write
  inside the session's own claimed tree — never another session's — and it is recorded in
  the guard log as `parallel-safe-unverifiable`.
- `write_verdict` → the two-branch legality rule of decision 7, applied to
  `Write|Edit|NotebookEdit` targets: allow when the target is inside the resolved change's
  worktree (subject to the existing read-only acceptance-suite rule); allow when the target
  is covered by a lane this role owns **and** that lane resolves outside every git working
  tree (`git -C <nearest existing ancestor> rev-parse --show-toplevel` finds nothing);
  refuse otherwise. The refusal for an in-repository lane path with no claim names the
  repair verbatim: add `CHANGE: <slug>` to the dispatch. This is what keeps the scribe's
  `~/.claude/projects/*/memory` writes legal with no claim at all, and puts the plan
  document inside the change it plans.
- `POLICED_ROLES` becomes `"builder test-author architect scribe executor deployer
  verifier reviewer debugger ops"` — every role holding Write, Edit, NotebookEdit, or Bash.
  The researcher and the ticketer are **exempt with a reason**: both deny those tools in
  frontmatter (`agents/researcher.md:7`, `agents/ticketer.md:6`,
  `disallowedTools: Edit, Write, NotebookEdit, Bash, Agent`), so there is nothing to
  police; Task 7 adds a frontmatter assertion that keeps that true. The orchestrator is
  the main session, policed by the dispatch guard.

The per-role Bash rule (decision 11) — four sets, four rules:

| Set | Roles | Rule for Bash |
|---|---|---|
| Change-confined | builder, test-author | Effective working directory must be inside the resolved change's worktree, and every `git -C <path>` must point inside it. Unchanged from today's builder rule (`:368`–`:406`), including the leading-`cd` allowance. |
| Integrator | executor, deployer | Not directory-confined. A git-mutating subcommand is refused unless it runs inside the resolved change's worktree, **or** the command is an invocation of `agent-team-workspace.sh` (`integrate`/`remove`) — the one sanctioned mutation of the shared checkout, which the closeout path needs. |
| Judge | verifier, reviewer | Not directory-confined, so the verifier still runs the acceptance suite and the reviewer still runs the plan lint from the shared checkout. Refused: any git-mutating subcommand, and any in-place file mutation whose resolvable target lies inside a git working tree. Write tools are absent by frontmatter, asserted in Task 7. |
| Diagnostic | debugger, ops | Identical to Judge. Cloud and outward mutations are untouched (decision 6). |

The pattern lists below are best-effort, not the guarantee: an interpreter-wrapped write
(`bash -c`, `python3 -c`), `find -delete`, or `xargs rm` can reach a file no pattern names.
For the Judge and Diagnostic roles, the real wall is the absence of `Write`, `Edit`, and
`NotebookEdit` in their frontmatter — asserted by Task 7's test — and the Bash patterns
below are defence in depth on top of that, not what the guarantee rests on.

The matcher skips every leading global option before looking for the subcommand —
`-C <path>`, `-c <k>=<v>`, `--git-dir=<path>` (and `--git-dir <path>`),
`--work-tree=<path>` (and `--work-tree <path>`), `--namespace=<name>` (and `--namespace
<name>`), `--exec-path[=<path>]`, `--no-pager`, `--no-replace-objects`,
`--literal-pathspecs`, `--bare`, `-p`, `--paginate`, and their space-separated forms where
git accepts one. An unrecognised leading option is skipped rather than treated as the
subcommand; a command whose subcommand cannot be identified at all is refused for the
Judge and Diagnostic sets rather than allowed — the classification fails closed, not open.
`--git-dir` and `--work-tree` in any form redirect git at another working tree, so for the
Integrator, Judge, and Diagnostic sets their presence is judged against the resolved
change worktree exactly as `-C` is.

The git-mutating subcommand set, matched as the first token that survives that skip: `add
am apply branch checkout cherry-pick clean clone commit config fetch gc init merge mv
notes prune pull push rebase reflog remote replace reset restore revert rm stash
submodule switch symbolic-ref tag update-ref worktree`. The head-ref subcommand — the one
word this project bans in prose, appearing here because the list matches literal command
tokens — is required: without it, a command of the form `git <that subcommand> -D
change/<slug>` deletes a change's ref and its history undetected, which is precisely the
loss this whole plan exists to prevent. In-place file mutation, matched as a command head:
`tee`, `sed -i`, `perl -i`, `cp`, `mv`, `rm`, `mkdir`, `touch`, `install`, `dd`, `chmod`,
`chown`, `ln`, `truncate`, and any `>` or `>>` redirection. For Judge and Diagnostic roles
these are refused only when the resolvable target is inside a git working tree, so a
temporary file under `$TMPDIR` and a suite's own scratch output stay legal.

**Reads are never gated**, and that is now a property of the wiring rather than a
sentence: the guard is registered on `PreToolUse(Write|Edit|NotebookEdit|Bash)` only, so
`Read`, `Glob`, and `Grep` never reach it.

**The rewrite of `tests/test_worktree_guard.sh:193`–`:280` in full** (SHOULD 11 — the
original plan named one case and broke six). Every case in that section resolves from a
transcript shape and carries neither a `session_id` nor any register state, so all of them
are rewritten together:

- `write_payload`, `edit_payload`, `bash_payload`, and `stop_payload` (`:58`–`:73`) gain a
  `session_id` field, and the fixture gains a register directory
  (`AGENT_TEAM_REGISTER_DIR="$WORK/register"`) plus a helper `card <slug> <worktree>
  <state>` that writes a timecard whose `pid`/`pid_start` are the test process's own, so
  the card is live for the duration of the run.
- `TR_POISONED` (`:218`–`:229`) — deleted. It exists to bless the live-dispatch-wins
  behaviour of a main-session recency scan; there is no recency scan left. Its intent is
  carried by a new case: a main-session transcript carrying two dispatch declarations
  yields no selector at all, and resolution comes from the register.
- `TR_TWO_LIVE` (`:231`–`:237`), `TR_BACKGROUND` (`:239`–`:246`), `TR_OTHER_ROLE`
  (`:248`–`:253`), `TR_ALL_DONE` (`:255`–`:262`) — deleted, all four. Each asserts which
  transcript-derived declaration wins; the register decides that now, and a resolved or
  unresolved dispatch has no bearing on it.
- The subagent-fallback case (`:264`–`:267`) — kept and inverted in meaning: it is no
  longer a fallback but the **only** transcript read, and it now supplies the `CHANGE:`
  selector rather than the worktree path. Its label becomes `a subagent's own dispatch
  prompt selects among its session's claims`.
- The ambiguity case (`:269`–`:279`) — replaced. It asserts today that ambiguity is
  *recorded* while the guard proceeds by recency; it must now assert that ambiguity
  **blocks**, and that the message names every candidate slug and the override line.
- New cases: `two live claims with no selector is a refusal naming both`; `a selector
  naming no live claim is a refusal naming both`; `one live claim resolves with no
  selector`; `a claim held by another session is not this session's candidate`; plus one
  `shared-checkout write refused: <role>` case for each of the ten policed roles, the
  four false-refusal cases from the acceptance suite's Stage 2 list, and one Bash case per
  row of the table above.

**Steps.**
1. [ ] Rewrite `tests/test_worktree_guard.sh:193`–`:280` exactly as enumerated above:
   delete the five listed cases, add `session_id` and the `card` helper to the fixture,
   and add the new cases with their labels. Every case prints `PASS [<label>]` on success.
2. [ ] Run `bash tests/test_worktree_guard.sh` — expect the new cases to fail and the
   confinement cases outside `:193`–`:280` to pass.
3. [ ] Implement: delete both transcript-scanning functions, add `resolve_change`,
   `own_dispatch_change`, `own_dispatch_parallel_safe`, `write_verdict`, and the per-role
   Bash rule; extend `POLICED_ROLES` to the ten roles.
4. [ ] Run `bash tests/test_worktree_guard.sh` — expect pass with `failed=0`.
5. [ ] `git commit -am "fix(worktree): confinement comes from a timecard, and ambiguity is a refusal"`

### Task 6: wire the guard to every writing role

**Files.** Modify `agents/{test-author,architect,scribe,executor,deployer,verifier,
reviewer,debugger,ops}.md` — nine frontmatter blocks; `agents/builder.md` already wires
the guard (`tests/test_agent_frontmatter.sh:51`–`:56`). Test
`tests/test_agent_frontmatter.sh`, `tests/test_worktree_guard.sh`.

**Interfaces consumed.** The `POLICED_ROLES` set from Task 5. This task is a separate
commit from Task 5 because a reviewer can reject the wiring while approving the rule, but
it is in the **same stage and the same push**: the rule without the wiring polices nobody,
and the wiring without the rule would refuse the architect and the scribe every write.

**Steps.**
1. [ ] Add to `tests/test_agent_frontmatter.sh`: for each of the ten policed roles, assert
   `agent-team-worktree-guard.sh <role>` appears in the file and appears inside the
   `PreToolUse:` section (the same `awk` shape used at `:53`); for `test-author`,
   `builder`, `executor`, `deployer` also assert the Stop/SubagentStop backstop (the shape
   at `:55`).
2. [ ] Run `bash tests/test_agent_frontmatter.sh` — expect failure naming the nine
   unwired roles.
3. [ ] Add the hook entry to the nine frontmatter blocks. The architect and the scribe keep
   their existing lane-guard entry as well: the lane guard decides which directories, the
   worktree guard decides which working tree.
4. [ ] Run `bash tests/test_agent_frontmatter.sh` and `bash tests/test_worktree_guard.sh`
   — expect both to pass.
5. [ ] `git commit -am "feat(guards): every writing role is wired to the workspace guard"`

### Task 7: the policy key, the role documents, and the README

**Committed last in Stage 2, and pushed with it** (decisions 8 and 9). Directive prose
reaches `origin/main` in the same push as the guard that enforces it, never ahead of it.

**Files.** Modify `policy/KEYS.md:20`; modify `agents/orchestrator.md:48`–`:53` and
`:123`–`:137`; modify `agents/builder.md`, `agents/test-author.md`,
`agents/architect.md`, `agents/scribe.md`, `agents/executor.md`, `agents/deployer.md`,
`agents/verifier.md`, `agents/reviewer.md`, `agents/debugger.md`, `agents/ops.md` where
each names its workspace — eleven of the thirteen `agents/*.md` counting the
orchestrator, with `researcher.md` and `ticketer.md` untouched because they hold no
writing or shell tools. Modify `README.md:105` (dispatch-guard row), `:106`
(worktree-guard row), and
`:107` (lane-guard row). Test `tests/test_agent_frontmatter.sh`.

**Interfaces produced.** The vocabulary every later reader quotes: *change*, *change
workspace*, *timecard*, *work register*, *writer slot*, *change disposition*.

Four prose facts this rewrite must state, because each one closes a finding:

- **The orchestrator declares; it never creates.** `agents/orchestrator.md:125`–`:127`
  today reads *"You create each builder's worktree before you dispatch it"* — the exact
  sentence to remove. In its place: every git-mutating dispatch carries
  `CHANGE: <task-slug>` as a bare slug at the start of a line, and the dispatch guard
  claims the timecard and builds or adopts the worktree. The path is derived, not passed:
  `<project>/.claude/worktrees/<slug>`.
- **The pre-existing contradiction is named as resolved** (NOTE 20). `:52` says *"Never
  mutate files, git, or systems yourself"* while `:125` said the orchestrator creates
  worktrees — a git mutation. The rewrite says in one sentence that the hook-side-effect
  design is what dissolves it, so the removal reads as intended rather than as an
  oversight.
- **A task that will produce a commit declares its change at intake**, before the first
  writing dispatch — including the architect's, so the plan document is written inside the
  change's workspace and integrates with it. This is also the answer to open issue #6
  (*"Status note has no defined home for PR-protected-main / multi-worktree tasks"*): the
  status note lives at `docs/STATUS-<task-slug>.md` **inside the change's workspace** and
  reaches the shared checkout by integration like any other file. The commit closes #6.
- **Parallelism is per change, and serialisation is per writer slot.** Two changes run
  concurrently by construction; two writers in one change are refused; a dispatch that
  writes nothing declares `PARALLEL_SAFE: this dispatch writes nothing` and is verified
  against that claim rather than trusted on it.

`policy/KEYS.md:20` becomes, in the file's one-line-per-key shape: *"workspace-isolation —
one worktree per change, claimed in the work register and created by the dispatch guard
before any agent writes; every git-mutating dispatch declares `CHANGE: <slug>` (consumers:
planning, tdd, debugging, finishing-a-branch)"*.

**Steps.**
1. [ ] Add to `tests/test_agent_frontmatter.sh`: no `agents/*.md` instructs an agent to
   create a worktree (a `grep -n` for `worktree add` and for `create .* worktree` across
   `agents/` that must find nothing, printing what it found on failure);
   `agents/orchestrator.md` contains the `CHANGE:` declaration rule; every one of the
   thirteen `agents/*.md` carries either a `tools:` line or a `disallowedTools:` line, so
   "which roles hold writing tools" is always answerable from the file; `researcher.md`
   and `ticketer.md` still deny `Write`, `Edit`, `NotebookEdit`, and `Bash`; and
   `verifier.md`, `reviewer.md`, `debugger.md`, `ops.md` carry none of `Write`, `Edit`,
   `NotebookEdit` in their `tools:` line (the token-exact `tr ',' '\n' | grep -qx` shape
   already used at `:36`–`:40`).
2. [ ] Run `bash tests/test_agent_frontmatter.sh` — expect failure naming
   `orchestrator.md` for its creation rule at `:125` and its missing `CHANGE:` rule.
3. [ ] Rewrite the prose in the eleven role documents, `policy/KEYS.md:20`, and the three
   `README.md` rows.
4. [ ] Run `bash tests/test_agent_frontmatter.sh` — expect pass.
5. [ ] `git commit -am "policy(workspace-isolation): the change owns the worktree, and a hook creates it" -m "Closes #6"`

**Stage 2 integration.** Run the eight suites this stage can affect —
`tests/test_dispatch_guard.sh`, `tests/test_worktree_guard.sh`,
`tests/test_agent_frontmatter.sh`, `tests/test_register.sh`,
`tests/test_register_concurrency.sh`, `tests/test_workspace.sh`,
`tests/test_hook_pin.sh`, `tests/test_install_touchpoints.sh` — each ending `failed=0` or
`FAIL=0`. Then push Tasks 4–7 to `origin/main` as one push. No task in this stage is
pushed on its own, because Task 7's prose and Task 4's guard are only consistent together.

## Stage 3 — Closeout and the operator view

### Task 8: closeout verifies integration; it never performs it

**Files.** Modify `hooks/agent_team_closeout.py`: add one check to `ledger_checks`
(`:352`–`:492`) and one helper beside `pending_code_paths` (`:318`–`:349`). Test
`tests/test_closeout_hook.sh`.

**Interfaces produced.** This is BLOCK 6's resolution: the hook stays a verifier, and the
integration is an executor dispatch it checks. That dispatch runs `agent-team-workspace.sh
integrate <project-root> <slug> <integration-ref> <session-id>`, passing its own payload
session id as the fourth argument so `workspace_integrate`'s membership check (Task 3) has
a session id to compare against rather than the pid branch alone. *(2026-08-17, Stage 1's
code review.)* `workspace_integrate` forwards that same session id to `register_release`
when it releases the card at the end, since that argument is load-bearing there too — an
omitted one would fall back to the pid branch alone, exactly as in Task 4.

- `held_claims(cwd)` → the live timecards for this project that this session is a member
  of, read by shelling out to `agent-team-register.sh session-claims`. Read-only.
- Ledger check 6, `change disposition`: when `held_claims` is non-empty, the final message
  must carry one line per held slug in the shape
  `CHANGE-DISPOSITION: <slug> | integrated into <ref> | kept for <tracker-ref> | abandoned`.
  A missing line blocks with the exact line to add. An `integrated` claim is **verified**,
  not believed: `git -C <cwd> merge-base --is-ancestor refs/heads/change/<slug> <ref>`
  must succeed, and the presence of the timecard is itself the counter-evidence — a claim
  reported as integrated whose card still exists means `workspace_integrate` did not run,
  and the block says so and names the command.
- The trigger is the existing gate's, unchanged and stated so no builder invents one: the
  check runs only where `ledger_checks` already runs — after `main()` has established that
  the session dispatched work (`total > 0`), that nothing is in flight (`in_flight` empty),
  and that this stop is not already priced (`total > state["acked_total"]`) — and it is
  skipped entirely when the final message carries `WORKFORCE_PAUSE: HUMAN_DECISION`. A
  mid-task pause therefore demands nothing and integrates nothing. The hook runs no git
  command that mutates, removes no tree, and deletes no timecard; the existing
  `MAX_BLOCKS = 3` cap still applies, so this check can never wedge a session.

**Steps.**
1. [ ] Add cases to `tests/test_closeout_hook.sh` with these labels: `a bare Stop with a
   live claim integrates nothing` (assert the fixture's worktree and timecard both still
   exist after the hook runs); `a completion claim with no change disposition is blocked`;
   `a HUMAN_DECISION pause with a live claim is allowed`; `an integrated disposition whose
   ref is not an ancestor is blocked`; `an integrated disposition whose timecard still
   exists is blocked`; `a kept disposition citing a tracker reference is allowed`.
2. [ ] Run `bash tests/test_closeout_hook.sh` — expect the new cases to fail.
3. [ ] Implement `held_claims` and ledger check 6.
4. [ ] Run `bash tests/test_closeout_hook.sh` — expect pass.
5. [ ] `git commit -am "feat(closeout): a held change needs a stated disposition, and integration is verified not claimed"`

### Task 9: the operator view

**Files.** Modify `tools/worktree-hygiene.sh` (argument handling at `:10`–`:20`, and a new
report section after the summary line at `:96`). Test `tests/test_worktree_hygiene.sh`.

**Interfaces produced.** `worktree-hygiene.sh <repo> [--register]`. Without the flag the
output is byte-identical to today's. With it, one additional block: one line per timecard
in this project — `slug`, holding session, pid liveness, `state`, writer slot and its age,
`opened`, and `stale` when the claim is older than `claim_stale_warn_seconds` — followed by
one line per registered worktree under `.claude/worktrees/` that **no** timecard covers,
marked `unclaimed` with the exact `git worktree remove` command. Still read-only: the
existing byte-identical-state assertion (`tests/test_worktree_hygiene.sh:72`–`:82`) covers
the new flag too.

**Steps.**
1. [ ] Add cases to `tests/test_worktree_hygiene.sh` with these labels: `hygiene lists a
   held claim and flags an unclaimed tree`; `hygiene marks a claim whose process is dead
   as reapable`; `hygiene without --register is unchanged`; `hygiene with --register
   mutates nothing`.
2. [ ] Run `bash tests/test_worktree_hygiene.sh` — expect the new cases to fail.
3. [ ] Implement the flag and the report block.
4. [ ] Run `bash tests/test_worktree_hygiene.sh` — expect pass.
5. [ ] `git commit -am "feat(hygiene): --register shows who holds what, and which trees nobody claims"`

**Stage 3 integration.** Run the ten suites — the eight from Stage 2 plus
`tests/test_closeout_hook.sh` and `tests/test_worktree_hygiene.sh` — and then
`bash tests/acceptance/test_workspace_isolation.sh`, which must now end `failed=0` with
every label from all three stage lists present. Then push.

## Acceptance criteria

Every mechanical check below runs the separately-authored acceptance suite
`tests/acceptance/test_workspace_isolation.sh`, which no builder may edit, and counts the
case labels it printed. A dropped case counts zero and fails its criterion.

- [ ] AC-1 (mechanical): two operating-system processes cannot both hold one change.
  Check: `bash tests/acceptance/test_workspace_isolation.sh | grep -c 'PASS \[exactly one of twenty claimants wins\]'`
  -> expects `1`.
- [ ] AC-2 (mechanical): a claim's liveness follows the session's harness process, not the
  short-lived hook process that wrote it.
  Check: `bash tests/acceptance/test_workspace_isolation.sh | grep -cE 'PASS \[(claim survives the hook process that created it|claim is reaped only after the session process exits|a recycled pid with a different start time is reaped)\]'`
  -> expects `3`.
- [ ] AC-3 (mechanical): a partially written or unreadable register never speaks for a
  holder.
  Check: `bash tests/acceptance/test_workspace_isolation.sh | grep -cE 'PASS \[(an empty timecard is reaped, not honoured as a holder|a missing register directory is an error, not a holder|two projects may hold the same slug at once)\]'`
  -> expects `3`.
- [ ] AC-4 (mechanical): a dead session's claim never blocks new work, and the tree it left
  behind is adopted rather than fought over.
  Check: `bash tests/acceptance/test_workspace_isolation.sh | grep -c 'PASS \[re-claim after reap adopts the surviving worktree\]'`
  -> expects `1`.
- [ ] AC-5 (mechanical): a same-session retry through either crash window resumes instead
  of refusing.
  Check: `bash tests/acceptance/test_workspace_isolation.sh | grep -cE 'PASS \[(a retry after a failed tree creation re-claims the same slug|a retry after a crash before ready completes the claim)\]'`
  -> expects `2`.
- [ ] AC-6 (mechanical): every one of the ten policed roles is refused a write to the
  shared checkout.
  Check: `bash tests/acceptance/test_workspace_isolation.sh | grep -c 'PASS \[shared-checkout write refused: '`
  -> expects `10`.
- [ ] AC-7 (mechanical): the four writes and shell runs the workflow itself depends on stay
  legal — the scribe's agent memory with no claim at all, the architect's plan inside the
  claimed tree, the verifier's acceptance-suite run from the shared checkout, and the
  reviewer's plan lint from the shared checkout.
  Check: `bash tests/acceptance/test_workspace_isolation.sh | grep -cE 'PASS \[(scribe memory write with no claim is allowed|architect plan write inside the claimed tree is allowed|verifier runs the acceptance suite from the shared checkout|reviewer runs the plan lint from the shared checkout)\]'`
  -> expects `4`.
- [ ] AC-8 (mechanical): no agent is ever handed a peer's workspace by a guess — an
  unresolvable workspace is a refusal that names both candidates, and a dispatch that
  declared it writes nothing may not write.
  Check: `bash tests/acceptance/test_workspace_isolation.sh | grep -cE 'PASS \[(two live claims with no selector is a refusal naming both|a selector naming no live claim is a refusal naming both|a dispatch declaring PARALLEL_SAFE may not write)\]'`
  -> expects `3`.
- [ ] AC-9 (mechanical): one change's writer slot admits one writer at a time and releases
  on its own TTL when the writer dies.
  Check: `bash tests/acceptance/test_workspace_isolation.sh | grep -cE 'PASS \[(two live writers on one change are refused|a stale writer slot is releasable)\]'`
  -> expects `2`.
- [ ] AC-10 (mechanical): a stop that is not a closeout integrates nothing, and a closeout
  that claims integration is checked against git.
  Check: `bash tests/acceptance/test_workspace_isolation.sh | grep -cE 'PASS \[(a bare Stop with a live claim integrates nothing|a completion claim with no change disposition is blocked|an integrated claim survives closeout only as a verified fact)\]'`
  -> expects `3`.
- [ ] AC-11 (mechanical): the installer carries the five new files (2026-08-17, Stage 1's
  code review: `agent-team-register-writer.sh` joined the set) through all five of its
  per-file touchpoints, so a rolled-back install leaves no debris and `install.sh --check`
  finds nothing missing.
  Check: `bash tests/acceptance/test_workspace_isolation.sh | grep -c 'PASS \[installer touchpoints cover the new hook files\]'`
  -> expects `1`.
- [ ] AC-12 (mechanical): the false-refusal ceiling — **deferred by construction to the
  first orchestrated task after landing**, and not checkable in this one. Record the
  landing timestamp `T` (the closeout of the task that integrates Stage 3) in that task's
  closeout receipt, then in the **next** task's closeout run
  Check: `jq -r --arg t "$T" 'select(.ts >= $t and .guard=="worktree" and .verdict=="block" and (.detail|test("no timecard|ambiguous|unresolvable")))' ~/.claude/logs/agent-team-telemetry/guard-blocks.jsonl | wc -l`
  -> expects `0` across that whole task, verified in that task's closeout and not in this
  one's. The `.ts` filter is what makes this criterion able to pass at all: the log
  persists across sessions and carries the 2026-08-04 incident's own blocks, so an
  unfiltered count fails forever on old data.
- [ ] AC-13 (mechanical): the operator can see who holds what and which trees nobody
  claims, without the report changing anything.
  Check: `bash tests/acceptance/test_workspace_isolation.sh | grep -c 'PASS \[hygiene lists a held claim and flags an unclaimed tree\]'`
  -> expects `1`.
- [ ] AC-14 (judgment): every refusal this change introduces names the durable fact it
  rests on and the one command or line that clears it. Judge: reviewer, in spec-fidelity
  mode, reading each new refusal message against the escape it offers. Bar: a "no" is any
  refusal a reader could not act on without opening the hook source, or one whose named
  escape is itself refused by another guard in this repository.

## Self-review

- **Coverage.** Every finding folded into this revision has a home: BLOCK 1 in Task 2
  (`register_session_process`, `register_alive`) and AC-2; BLOCK 2 in decision 7 and Task
  5 (`write_verdict`) and AC-7; BLOCK 3 in decision 12 and Task 5
  (`own_dispatch_change`) and AC-8; BLOCK 4 in decision 9 and the Stage 2 single push with
  Task 7 last; BLOCK 5 in Task 3 (`workspace_ensure` step 3) and AC-4; BLOCK 6 in decision
  2 and Task 8 and AC-10; BLOCK 7 in decision 11's table and AC-6/AC-7. SHOULD 8 in Task
  5's `POLICED_ROLES` and its stated researcher/ticketer exemption; SHOULD 9 in
  `register_root` and `register_project_key`; SHOULD 10 in Task 4's resumption paragraph
  and AC-5; SHOULD 11 in Task 5's full enumeration of the rewritten test section; SHOULD 12
  in AC-12; SHOULD 13 in `register_alive` including the EPERM note; SHOULD 14 in decision
  10; SHOULD 15 in decision 1's amendment and `register_writer_acquire`. NOTE 16's stale
  references are corrected throughout (the orchestrator's creation rule is at `:123`–`:137`,
  not `:48`–`:52`; thirteen agent documents, not twelve; the README rows are `:105`–`:107`;
  AC-6 names the verifier). NOTE 17's three constraints are in decision 3 and Task 2. NOTE
  18 is answered in Task 7 (`Closes #6`). NOTE 19 is answered in Task 4
  (`CHANGE_REQUIRED_ROLES` includes executor and deployer; the transcript collision scan is
  retired). NOTE 20 is named in Task 7's prose facts.
- **Placeholder scan.** No "TBD", no "TODO", no "similar to Task N", no "implement later",
  no interface referenced that no task defines. Every exit code, marker literal, field
  name, function signature, and test-case label a later task quotes is defined in an
  earlier one.
- **Consistency.** The marker literals (`CHANGE:`, `PARALLEL_SAFE: this dispatch writes
  nothing`, `CHANGE-DISPOSITION:`), the derived names
  (`<project>/.claude/worktrees/<slug>`, `refs/heads/change/<slug>`), the exit codes (0
  ok, 3 held, 4 no session process, 5 register unusable, 6 bad slug, 7 workspace unusable,
  8 not integrable), and the timecard field names are used identically in every task and
  every criterion.
- **Red commit.** Task 1 lands a deliberately red test, stated as such in its commit
  message, and Task 2 turns it green — the only red commit in the plan. The acceptance
  suite is also committed red, by the test-author, before any builder runs; that is the
  route's design, not an exception to it.
- **Live safety controls.** Stages 2 and 3 rewrite controls that are themselves protecting
  the session doing the work. Hook pinning means an installed repair does not change rules
  under a running session; that is verified by `tests/test_hook_pin.sh` and must be re-run
  after each stage. Agent documents are **not** pinned, which is why nothing installs
  mid-task and why decision 9 exists.
- **Not covered, deliberately.** Cloud-resource claims (decision 6); removing the
  orchestrator's Bash (open question 2); the `~/.claude/agent-dispatch-lint.STOP` kill
  switch, which is Jay's own machine-level escape hatch and not this repo's to remove;
  and end-to-end proof of the new mechanism in a live orchestrated session, which is AC-12
  and belongs to the first task after landing. The file-size debt this list once carried —
  `tests/test_register.sh` sitting at 570 lines against this repository's ~300-line
  guideline — is paid: the unit tier is split three ways by decision, not by case-trimming
  (`tests/test_register.sh`, the register's decisions, at 277 lines; `tests/test_register_lifecycle.sh`,
  a card's lifetime; `tests/test_register_races.sh`, the multi-process race tier; sharing
  `tests/lib/register-fixture.sh`), so no entry belongs here for it. What keeps the split
  unit tier fast despite running four times the case count of the original file: the two
  unit-tier suites run their own cases concurrently, each case against its own private
  fixture directory and register root, so the tier's wall time is close to its slowest
  single case rather than the sum of all of them; the race tier stays sequential on purpose,
  because its cases start real processes and assert what their interleaving produced, and a
  second race running beside them would compete for the very cores that interleaving needs.
