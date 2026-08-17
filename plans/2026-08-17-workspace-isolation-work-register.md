# Workspace isolation: the work register

**Goal.** Make it structurally impossible for two agents — in one session or in
different operating-system processes — to write into the same working directory, without
refusing honest work.

**Architecture.** The unit of isolation becomes the *change*, not the agent: one linked
git worktree per change, shared by every agent contributing to that change, with at most
one live writer in it at a time. Ownership is a durable fact on disk — a **timecard**
file per claim in a machine-scoped **work register**, created with an exclusive-create
that the filesystem itself serialises — so guards read facts instead of inferring
identity from conversation history. Worktree creation, the timecard, and integration are
performed by hooks as a side effect of a declaration in the dispatch, so no agent ever
runs a mutating git command.

**Tech stack.** Bash hooks + `jq` (existing guard convention), Python 3 only where a
hook already uses it, POSIX filesystem primitives for exclusion. No new dependencies,
so `policy:dependency-freshness` pins nothing in this plan.

## Global constraints

- `policy:workspace-isolation` — resolved from **project policy** (`policy/KEYS.md:20`),
  verbatim: *"one unique worktree per builder, created before any code is touched
  (consumers: planning, tdd, debugging, finishing-a-branch)"*. **This plan amends that
  key** (Task 1): the unit becomes the change, not the builder, and creation moves from
  the orchestrator to a hook. Until Task 1 lands, the existing wording governs.
- `policy:dependency-freshness` — resolved from **project policy**
  (`policy/KEYS.md:19`); no dependency is added or pinned by this plan, so the key is
  consulted and not exercised.
- Hooks are pinned per session (`hooks/agent-team-pin.sh`), so two guard builds will
  read one register concurrently. Every register format change is additive and carries
  a schema version.
- Tasks below touch disjoint files and are ordered; each stage produces working,
  testable software on its own.
- Security pass: the register stores no credentials; timecards hold session id, process
  id, change slug, paths, timestamps only. Refusal messages quote paths, never file
  contents.

## Decisions resolved by the panel (2026-08-17, debate mode)

1. **Owner and writer are separate fields.** A timecard names the change's owning
   session *and* the currently-writing agent slot. Two builders repairing one change
   share the tree but never hold the writer slot at once. (Adzic: H1 removed the
   accidental serialisation that per-builder trees provided.)
2. **Workspace administration is a hook side effect, not an orchestrator command.**
   The orchestrator declares `CHANGE: <slug>` in a dispatch; the dispatch guard claims
   the timecard, creates the worktree, and rewrites nothing else. This resolves Fowler's
   contradiction — the orchestrator can lose Bash and still get workspaces — and removes
   the class of failure where a malformed or missing path burned seven dispatches.
3. **One file per claim, created with `O_EXCL`.** Mutual exclusion is the filesystem's
   atomic create, not a lock file and not an append to a shared list. This answers
   Nygard's lost-update objection and Hohpe's ordering question at once: no two
   processes can both create the same claim.
4. **Ordering: claim first, tree second, ready third.** A timecard without a tree is
   reaped by liveness. A tree without a timecard is refused and reported by hygiene.
   A partially written claim is never authoritative — reconciliation is
   `reap`, never deadlock. (Hohpe.)
5. **`session_id` survives resume — verified.** All three live sessions examined span
   14→17 August in one file with one id each; no id is shared across files. A cleared or
   forked session mints a new id, so reaping is by process liveness, never by id match.
6. **Cloud mutations are an explicit non-goal.** A workspace timecard is the wrong claim
   type for an IAM policy. Naming it out of scope beats an exemption inside the gate.
   (Hightower.)
7. **Every refusal carries its escape.** The message names the durable fact and the one
   command that resolves it, and the existing human-override marker
   (`WORKFORCE_OVERRIDE: lane-refusal`) is extended to workspace claims. False refusal
   is the failure mode with the worst history here; it gets an acceptance criterion of
   its own (Cockburn, Wiegers).
8. **Concurrency is tested with real processes before the feature is built** (Crispin),
   and the role documents are rewritten in the same change as the mechanism (Gregory).

## Open questions the tasks proceed on

- **Where an unattended warning goes.** Assumption: the guard log
  (`~/.claude/logs/agent-team-telemetry/guard-blocks.jsonl`) plus a line in the closeout
  receipt, since that is the one surface the human always reads. Revisit if closeout
  noise becomes the complaint.
- **Whether the orchestrator loses Bash in this change or the next.** Assumption: not in
  this change. The register gate (Stage 3) makes its shell harmless first; removing the
  tool is a separate, reviewable step so a regression in the gate does not blind the
  orchestrator at the same moment.

---

## Stage 1 — Foundation

### Task 1: amend the policy key and the role documents

**Files.** Modify `policy/KEYS.md:20`; modify all twelve `agents/*.md` workspace prose;
modify `README.md:106`. Test `tests/test_agent_frontmatter.sh`.

**Interfaces.** Produces the vocabulary every later task quotes: *change*, *change
workspace*, *timecard*, *work register*, *writer slot*.

**Steps.**
1. [ ] Add to `tests/test_agent_frontmatter.sh` an assertion that no `agents/*.md`
   instructs an agent to create a worktree, and that `agents/orchestrator.md` states
   workspaces are requested by declaration, not created.
2. [ ] Run `bash tests/test_agent_frontmatter.sh` — expect failure naming
   `orchestrator.md` (its `:48`–`:52` prose and the "orchestrator owns creation" rule).
3. [ ] Rewrite the prose in all twelve role documents and `policy/KEYS.md:20`.
4. [ ] Run `bash tests/test_agent_frontmatter.sh` — expect pass.
5. [ ] `git commit -am "policy(workspace-isolation): the change owns the worktree, and a hook creates it"`

### Task 2: the concurrency test harness

**Files.** Create `tests/lib/concurrency.sh`, `tests/test_register_concurrency.sh`.

**Interfaces.** Exports `spawn_claimants <n> <register-dir> <slug>` (n real background
processes racing one claim) and `assert_exactly_one_winner`. Every later stage's test
consumes these.

**Steps.**
1. [ ] Write `tests/test_register_concurrency.sh` asserting that twenty concurrent
   processes claiming one slug produce exactly one success and nineteen refusals.
2. [ ] Run it — expect failure: `register-claim.sh: No such file or directory`.
3. [ ] Leave it red; Task 3 turns it green. Commit the harness alone:
   `git commit -am "test(register): a real multi-process race harness, red until the register exists"`

### Task 3: the register primitive

**Files.** Create `hooks/agent-team-register.sh`. Test
`tests/test_register_concurrency.sh` (from Task 2), `tests/test_register.sh`.

**Interfaces.**
- `register_claim <slug> <session-id> <pid> <worktree-path>` → exit 0 and prints the
  timecard path, or exit 3 and prints the current holder. Creates
  `$REGISTER_DIR/<slug>.json` with `set -o noclobber` redirection (the shell's
  `O_EXCL`), schema `{"v":1,"slug","session","pid","worktree","state":"claiming",
  "opened","heartbeat","writer":null}`.
- `register_ready <slug>` → `state:"ready"`.
- `register_holder <slug>` → prints the JSON or nothing.
- `register_writer_acquire <slug> <agent-slot>` / `register_writer_release <slug>`.
- `register_heartbeat <slug>`; `register_reap <register-dir>` — removes any timecard
  whose `pid` is not live (`kill -0`).
- Unknown JSON fields are preserved across every rewrite (temp file + `mv`), so an older
  pinned guard cannot destroy a newer guard's data.

**Steps.**
1. [ ] Write `tests/test_register.sh` covering: claim succeeds; second claim by another
   session exits 3 and names the holder; `register_reap` removes a dead pid's timecard
   and leaves a live one; an unknown field survives a heartbeat.
2. [ ] Run both test files — expect failure, `agent-team-register.sh` missing.
3. [ ] Implement `hooks/agent-team-register.sh`.
4. [ ] Run both — expect pass, including exactly-one-winner across twenty processes.
5. [ ] `git commit -am "feat(register): a timecard per change, exclusive by filesystem create"`

## Stage 2 — Administration by declaration

### Task 4: the dispatch guard claims and creates

**Files.** Modify `hooks/agent-team-dispatch-guard.sh` (the
`WORKTREE_REQUIRED_ROLES` block, lines 286–470). Test
`tests/test_dispatch_guard.sh`.

**Interfaces.** Consumes `register_claim`/`register_holder`/`register_writer_acquire`.
A dispatch declares `CHANGE: <slug>`; the guard resolves the workspace path from the
claim, creates the worktree when the claim is new, injects the resolved path into the
refusal-free path, and refuses when another *live* session holds the slug — naming that
session and the reaping command.

**Steps.**
1. [ ] Add tests: a dispatch with `CHANGE:` and no existing claim creates the tree and
   succeeds; the same slug from a second session is refused with the holder named; a
   dispatch whose slug is held by a dead pid succeeds after automatic reaping; two live
   writers on one slug are refused.
2. [ ] Run `bash tests/test_dispatch_guard.sh` — expect the four new cases to fail.
3. [ ] Implement, deleting the `WORKTREE:`-path shape checks that creation makes moot.
4. [ ] Run — expect pass.
5. [ ] `git commit -am "feat(dispatch): a change declaration claims its workspace and the hook builds it"`

### Task 5: retire resolve-by-recency

**Files.** Modify `hooks/agent-team-worktree-guard.sh` (`declared_worktree`,
`live_declaration_count`, lines 203–333). Modify `tests/test_worktree_guard.sh` —
**delete** the case at `:270` that blesses recency, replacing it in the same commit.

**Interfaces.** The guard resolves confinement from `register_holder` keyed on the
payload's `session_id`, never from the transcript. More than one candidate workspace for
one session is a refusal that names both.

**Steps.**
1. [ ] Replace `:270` with its inverse: two live claims for one session must **block**,
   and the message must name both slugs and the override line.
2. [ ] Run `bash tests/test_worktree_guard.sh` — expect the new case to fail.
3. [ ] Rewrite resolution to read the register; delete both transcript-scanning
   functions and the task-notification gap with them.
4. [ ] Run — expect pass, and confirm the deleted test's replacement is green.
5. [ ] `git commit -am "fix(worktree): ambiguity is a refusal, because a guess aims a builder at a peer's tree"`

### Task 6: extend confinement to every writer

**Files.** Modify `hooks/agent-team-worktree-guard.sh:46` (`POLICED_ROLES`); modify
`agents/{architect,scribe,test-author,executor,deployer,verifier,reviewer}.md`
frontmatter to register the guard. Test `tests/test_worktree_guard.sh`,
`tests/test_agent_frontmatter.sh`.

**Interfaces.** `POLICED_ROLES` becomes every role holding Write, Edit, NotebookEdit, or
Bash. Verifier and reviewer are policed *and* denied writes outright — their concern is
judgment, not production.

**Steps.**
1. [ ] Add tests: a scribe write to the shared checkout is refused; a test-author write
   lands in the change's tree; a reviewer write is refused anywhere.
2. [ ] Run — expect failure (today only `builder` is policed).
3. [ ] Implement, and add the guard to the seven frontmatter blocks.
4. [ ] Run both test files — expect pass.
5. [ ] `git commit -am "feat(guards): every writer is confined to the change's workspace, and judges write nothing"`

## Stage 3 — The gate and the view

### Task 7: no mutation without a live timecard

**Files.** Modify `hooks/agent-team-worktree-guard.sh` (PreToolUse branch). Test
`tests/test_worktree_guard.sh`.

**Interfaces.** A write is legal only when a live timecard covers this `session_id` and
the target lies inside that timecard's worktree. Reads are never gated. `PARALLEL_SAFE`
is redefined to mean *writes nothing* and is verified by the same target check rather
than accepted as an assertion.

**Steps.**
1. [ ] Add tests: a write with no timecard is refused; a `PARALLEL_SAFE` dispatch that
   writes is refused; a read with no timecard succeeds.
2. [ ] Run — expect failure.
3. [ ] Implement.
4. [ ] Run — expect pass.
5. [ ] `git commit -am "feat(guards): a mutation requires a live timecard; reads never do"`

### Task 8: integration and the operator view

**Files.** Modify `hooks/agent_team_closeout.py`; modify `tools/worktree-hygiene.sh`.
Test `tests/test_worktree_hygiene.sh`, `tests/test_closeout_hook.sh`.

**Interfaces.** Closeout integrates the change's tree, releases the writer slot,
punches out the timecard, and removes the tree only after integration. Hygiene gains
`--register`: who holds what, since when, which claims are stale, and which trees have
no timecard.

**Steps.**
1. [ ] Add tests: closeout releases the claim and leaves no tree behind; hygiene lists a
   held claim and flags an unclaimed tree.
2. [ ] Run both — expect failure.
3. [ ] Implement.
4. [ ] Run both — expect pass.
5. [ ] `git commit -am "feat(closeout): integration punches the timecard out, and hygiene shows the field"`

## Acceptance criteria

- [ ] AC-1 (mechanical): two sessions cannot hold one change. Check:
  `bash tests/test_register_concurrency.sh` -> expects exactly one winner of twenty.
- [ ] AC-2 (mechanical): no builder is handed another dispatch's workspace. Check:
  `bash tests/test_worktree_guard.sh` -> expects the two-live-claims case to block and
  name both slugs.
- [ ] AC-3 (mechanical): no agent writes the shared checkout. Check:
  `bash tests/test_worktree_guard.sh` -> expects refusal for scribe, architect,
  test-author, executor, reviewer targets at the checkout root.
- [ ] AC-4 (mechanical): a dead session's claim never blocks new work. Check:
  `bash tests/test_register.sh` -> expects reap of a dead pid and survival of a live one.
- [ ] AC-5 (mechanical): the bar and the code share a base. Check:
  `bash tests/test_dispatch_guard.sh` -> expects test-author and builder on one slug to
  resolve to one worktree path.
- [ ] AC-6 (mechanical): false-refusal ceiling. Check:
  `jq -r 'select(.guard=="worktree" and .verdict=="block")' ~/.claude/logs/agent-team-telemetry/guard-blocks.jsonl | wc -l`
  -> expects zero blocks attributable to an unresolvable workspace across one full
  orchestrated task after landing.
- [ ] AC-7 (judgment): every refusal names the durable fact and the command that
  resolves it. Judge: reviewer, in spec-fidelity mode. Bar: a "no" is any refusal string
  a reader cannot act on without reading the hook source.

## Self-review

- No task depends on another's uncommitted work; Stage 1 is independently shippable.
- Task 2 lands a deliberately red test, stated as such in its commit message, and Task 3
  turns it green — the only red-commit in the plan.
- Stages 2 and 3 rewrite live safety controls. Hook pinning means an installed repair
  does not change rules under a running session; that is verified by
  `tests/test_hook_pin.sh` and must be re-run after each stage.
- Not covered, deliberately: cloud-resource claims (decision 6), removing the
  orchestrator's Bash (open question 2), and the `~/.claude/agent-dispatch-lint.STOP`
  kill switch, which is Jay's own machine-level escape hatch and not this repo's to
  remove.
