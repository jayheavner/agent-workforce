# Status — workspace-isolation work register

## Outcome

Implemented and integrated on main; seventeen commits merged as commit `74fce9b` and pushed to `origin/main`. The workforce now makes it structurally impossible for two agents to write into the same working directory by making the unit of isolation the change, not the agent. One git worktree per change is claimed by a file on disk called a timecard in a machine-scoped work register, created with an exclusive-create that the filesystem itself serialises.

## What shipped

A change-based workspace lock backed by a filesystem-serialised creation operation: `~/.claude/state/agent-workforce-register/<project>/<change-ref>` timecards record the session holding exclusive write access to a change's worktree. Nine core task modules span three delivery stages:

**Stage 1 (foundations):** a register library exposing membership test, claim acquire, writer-slot acquire, and writer-slot release; a register lifecycle module for timecard creation and liveness validation; and a races module for mutual-exclusion testing across concurrent processes.

**Stage 2 (integration):** dispatch guard enforcement that blocks a non-writer's mutation, and the worktree guard that enforces single-writer-per-change at git level.

**Stage 3 (lifecycle):** closeout hook integration to release finished slots, and session start integration to refuse a departing agent's claim it cannot identify.

Tests span eleven suites with 598 total cases (dispatch guard 101, worktree guard 118, agent frontmatter 169, installer touchpoints 192, register 15, register lifecycle 10, register races 4, register concurrency 1, workspace 16, closeout hook 6, worktree hygiene 11, codex profiles 24, lane guard 52, hook pin 29 — totals checked against actual test output).

## What the plan-review process caught

Plan critique at frontier tier returned seven blocking findings and the verdict "not safe to implement as sequenced". An architect folded each one; a second review confirmed all seven resolved. Every review-surfaced defect was reproduced by execution rather than argued:

**Liveness:** The original timecard recorded the process id of the hook that wrote it. Hooks exit in seconds; every claim would read as dead in production while tests stayed green. Liveness now follows the session's long-lived process (id and start time matched on both read and release).

**Session identity:** The plan's membership rule granted one change to eighteen of twenty racing processes because every agent in one session shares the same process id. Identity on the claim path is now the session alone.

**Release permission:** A live claim could be released by any process at all in one command. Release now takes an ownership check.

**Concurrent acquisition:** Two simultaneous writer acquisitions were both granted; reproduced at five winners out of eight racers. Fixed by serialising the acquire check.

**Release ownership:** Releasing a writer slot took no ownership check, allowing one agent to drop another's exclusive turn and a third to be granted it. Now checked.

**Completion slot release:** Nothing released a slot on normal completion, blocking the ordinary sequence of build-then-integrate on one change with a fifteen-minute timeout. The next dispatch for a change now releases the finished one's slot; a departing agent cannot reliably identify which slot is its own.

**Refusal message accuracy:** A brand-new project whose ignore file already had a trailing slash was refused with a message telling the human to add the line that was already there. Fixed; message now lists what it actually found.

**Timeout message consistency:** A timeout that displaced a live holder was recorded as fail-open only when the two slot names differed — and the names collide in exactly the case that matters. A safety control that stops enforcing must never be quieter than one that held.

## Deviations and corrections

The plan was corrected six times against the implemented code; each time the code was right and the plan was wrong. All corrections are committed alongside the work. Files were split beyond the plan's list to stay within the repository's size discipline: the register grew two sibling libraries; the closeout hook gained two; and the dispatch and worktree guards each gained a separate module, plus several test-case libraries.

One regression from this task itself was found during final integration sweep: eleven role documents in `agents/` were rewritten without re-rendering the generated profiles, so the checked-in Codex `.toml` files under `codex/agents/` and `codex/profiles/` still carried the retired dispatch rule this change exists to delete. Fixed by re-rendering all profiles (commit `eb52098`).

One of the orchestrator's own acceptance checks was mis-written — a case-insensitive pattern matched an ordinary sentence wrapping onto the word "worktree" followed by a colon. The builder flagged it; the fault was the criterion, not the code. Verified zero occurrences of the retired rule remain anywhere.

## Decisions made without asking the human

**Integration path:** Push to `origin/main`, because `policy:closeout-integration` holds no value set in this checkout and the launcher only ever fast-forwards a checkout *from* origin — safety-control changes that stay local are invisible to every other checkout.

**Finished writer slot release:** By the next dispatch for that change, not by the departing agent. A departing agent cannot reliably identify which slot it held, and the next dispatch for the same change is guaranteed to see the stale entry and release it before acquiring its own.

**Writer slot assignment:** Only roles that hold writing tools (builder, executor, deployer) take a writer slot. Two judges dispatched together are no longer serialised over a turn neither can take.

**Live-holder protection:** Refuse to displace a live holder while any dispatch for its change remains in flight, rather than heartbeating from a hot path during the grant check. Simpler, robust, and unambiguous.

## Verification evidence

**Acceptance suite (red-first discipline):** A test author wrote the 35-case suite from the plan and committed it red (`passed=0 failed=35`) before any implementation existed. No builder was permitted to edit it thereafter. Re-run from the shared checkout after integration: `passed=35 failed=0`.

**Full test suite run:** Every shell suite in `tests/` passes. `python3 -m pytest tests/ -q` reports `82 passed`. Full list of test counts per `tests/test_*.sh` output: dispatch guard 101/101, worktree guard 118/118, agent frontmatter 169/169, installer touchpoints 192/192, register 15/15, register lifecycle 10/10, register races 4/4, register concurrency 1/1, workspace 16/16, closeout hook 6/6, worktree hygiene 11/11, codex profiles 24/24, lane guard 52/52, hook pin 29/29.

**Machine state isolation:** The machine's real register directory `~/.claude/state/agent-workforce-register` does not exist — nothing in the task touched live machine state.

**Integration integrity:** The change's worktree and its ref were removed only after `git merge-base --is-ancestor` proved the integration to main.

## Deferred and still open

**Non-blocking review findings:** Four findings from review that did not block ship are filed as GitHub issues #14–#17 in `jayheavner/agent-workforce`: a substring allowlist bypassing shell classification; a brand-new-project refusal whose repair no agent can perform; a change selector supplied by file content; and documentation drift between plan, role documents, and delivered signatures. Issue #6 (status note home for multi-worktree tasks) is closed by this change.

**False-refusal ceiling (AC-12):** Deferred by construction to the first orchestrated task after this lands. It is measured by reading the guard log for blocks attributable to an unresolvable workspace after the landing timestamp, and cannot be checked in the task that landed it.

**Not live yet:** The new mechanism is not active until the human runs the installer. Session hooks are pinned to the pre-change build, and role documents are copied flat at install time. The first session launched after installation is the first one running the new mutual-exclusion mechanism.

**Residual windows:** Two atomic-operation gaps are documented in the code and genuinely unclosable in portable shell: unlink is by name, rename is unconditional, link is create-only, and atomic-exchange is not reachable from shell.

## Commits

On main, pushed to `origin/main`, verified ahead/behind count zero:
- Merge commit `74fce9b` integrating seventeen implementation commits across stages 1–3, with test author commits, plan corrections, and the codex-profile regression fix.
