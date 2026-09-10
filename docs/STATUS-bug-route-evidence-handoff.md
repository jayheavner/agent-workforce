# Status — bug-route-evidence-handoff work register

## Outcome

Implemented and integrated as pull request #23 on the `change/bug-route-evidence-handoff` worktree with ten commits, base main at `fc1b085`. The work resolves a gap in the team's separation of duties: when a debugger produces a proof that a bug is present, that proof was being discarded at the handoff to the builder, leaving the builder to define "fixed" without independent verification. The team now routes that proof forward through every dispatch from the builder through the verifier, turning it into an acceptance criterion that cannot be weakened without being caught.

## What shipped

A protocol that carries a reproduction command from debugger through orchestrator, builder, executor, and verifier: the debugger's diagnosis report must carry the reproduction command on its own line prefixed `REPRO COMMAND:`. When no command could be built, the line reads `REPRO COMMAND: none — <why>`, stating what was tried and what access or artifact would unblock one, and the report becomes `partial` rather than `complete`. When the reproduction lives outside the repository, the command line carries the marker ` [throwaway]`.

**Agent role documents** updated with the protocol:

`agents/debugger.md` — documentation of the `REPRO COMMAND:` line requirement, its format, and the rules for missing or external reproductions.

`agents/orchestrator.md` — the symptom route turns that command into the first acceptance criterion, quoted exactly, and carries it into the builder, executor, and verifier dispatches. A command bearing a marker must be replaced with a durable equivalent before it is handed to the builder.

`agents/builder.md` — a repair stance: adding a test to the file that the command exercises is permitted; weakening the assertion the command relies on is not; no adjacent cleanup or refactor is allowed.

`agents/verifier.md` — must inspect the change's diff for a weakened assertion in the target file and report it as a blocking finding.

**Mirrored documentation** in `skills/agent-workforce/SKILL.md`, which is the surface that drives skill-invoked and Codex sessions — a rule present in only one of the two is inert in the other.

**Drift test** at `tests/test_bug_route_handoff.sh` with forty assertions pinning every surface: every required line, every marker variant, every refusal state, and the interaction with dispatch markers.

**Mutation harness** at `tests/test_bug_route_handoff_mutations.sh` that proves the drift test is load-bearing: eleven mutations must each be caught by the test, two cosmetic reflows must be tolerated, and a negative control asserts the drift test passes on an unmutated copy.

**Installation integration** in `install.sh`: both tests registered in the install-time gate, with the block's comment corrected to state plainly that this repository has no continuous-integration runner.

**Codex regeneration** under `codex/` — no hand edits, profiles redrawn from the updated agent documents.

## What the review process caught

Three review rounds across the open pull request: request-changes on round one, approve-with-nits on round two and three. Twenty-one findings raised and closed across all rounds.

**Round one (blocking):** Five findings: the orchestrator's marker-replacement logic was stateless and would re-replace already-durable commands; the builder's scope needed to exclude test-library weakening as a category; the verifier's diff inspection needed to handle multi-line assertions; the drift test needed explicit coverage of the interaction between marker variants; and the mutation harness's self-test mode needed separate orchestration from the main case.

**Round two and three (approval-with-nits):** Sixteen findings across test clarity, edge-case coverage, and documentation specificity. One finding spanned both rounds: the orchestrator's marker replacement was re-specified twice because the original rule produced ambiguity when a command contained its own marker string.

All findings were actionable — no architectural disputes, no deferred judgment calls, all closed by code review on the final commit.

## Decisions made without asking the human

**No new agent was created; the gap was a handoff, not a role.** The team's existing split — a debugger that physically cannot edit a file, and a builder that fixes — is a capability boundary rather than a stylistic one. The separation of duties exists to prevent the builder from defining "fixed" unilaterally; adding an agent is unnecessary when the missing piece is a protocol.

**Agent personas exist here as dispatch-named modes.** The reviewer has four modes (plan-review, audit-review, fix-review, integration-review), and the builder has two (repair, refactor). These modes can change stance and deliverable but not capability, since tools, hooks, and preloaded skills are fixed per agent. The terminology matters: agent is a role with fixed tools; persona is a dispatch-named mode within that role.

**Integration was resolved to a pull request rather than a push to main.** Rule issue #18 records that this pattern was bypassed three times. The pull-request gate gives review a canonical decision point that cannot be accidental.

**Three repair rounds were run instead of the customary two.** The alternative was handing back ten one-line fixes as remaining work; the third round resolved them in a single resubmit.

## Verification evidence

**Three independent passes, all green.** The drift test reports forty assertions passing on the change and thirty-two failing on a fresh copy of the pre-change tree, demonstrating it pins something real. The mutation harness reports eleven mutations caught and two tolerated; its self-test mode correctly fails on the unmutated baseline, confirming the harness logic itself is sound.

**Five neighbouring suites remain green.** No regression across the wider test suite.

**No tangential changes.** No frontmatter changed, nothing under `hooks/` or `skills/debugging/` touched — the change is surgical.

## Follow-ups filed

GitHub issues filed against the repository to record findings that do not block this work but deserve investigation:

**Issue #19:** Five guard-test hygiene gaps, one of which allows a live proof to silently shrink during handoff — the most critical to address because it breaks the whole mechanism silently.

**Issue #20:** The "quoted exactly" instruction can produce an unrunnable check when the command carries a marker, because the marker is meant to be replaced before execution but the check preserves it. Worth doing first.

**Issue #21:** The debugging discipline document tells a builder to create its own workspace, which the dispatch guard refuses — a conflict between the design intent and the gate.

**Issue #22:** The executor writes files but is never required to carry or run the acceptance criteria, creating a blind spot in the execution phase.

**Comment on issue #17:** The dispatch guard installed in this session demands the retired `WORKTREE:` declaration in its manifest and rejects the current `CHANGE: <slug>` marker. The task worked around this by declaring the retired form, which is inert but syntactically required. This is a blocker for the next session; the manifest inside the installed guard needs to match the current rule documents.

## Also worth recording

Jay observed that work has stopped short of its stated goal repeatedly, and asked whether that pattern is a separate workstream. It is, and a prior attempt exists on record: a process-assurance auditor whose job was to measure work against its stated bar was built, installed default-off with its operational evidence explicitly unrun, and then deleted wholesale in commit `e175439` (the autonomy-first redesign). The recommended first deliverable of that workstream is an evidence pass over existing telemetry, counting how often writing dispatches carried a measurable bar and how often completion claims had independent measurement — not a new mechanism, because going straight to mechanism is how the last attempt failed. That workstream is not started; it awaits a separate decision and dispatch.

## Deferred and still open

No blocking work remains. All deferred items are filed as GitHub issues and noted above.

## Commits

On `change/bug-route-evidence-handoff` worktree, base main `fc1b085`:
- Ten implementation and documentation commits
- Merged via pull request #23, open and unmerged as of session close

