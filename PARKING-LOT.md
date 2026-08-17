# Parking Lot

Ideas raised during design that are deliberately deferred — not rejected. Each entry records the idea, why it's attractive, why it's parked, and where it would plug in if picked up, so the reasoning isn't lost.

---

## Cross-vendor critic for high-stakes adversarial roles

**Raised:** 2026-07-10, during the decision-discipline design pass.

**Idea.** For the most adversarial roles — the spec critic and the security reviewer — run the critic on a *non-Claude* model (e.g. an OpenAI GPT/o-series model) instead of a different Claude tier, to maximize independence.

**Why it's attractive.** The entire value of an independent critic is *different blind spots*. Opus and Fable share a training lineage, so they can rationalize the same false binary the same way — a Fable critic may nod along at exactly the buried tradeoff an Opus architect produced. A cross-vendor model has genuinely different priors and failure modes, which is the strongest independence available, aimed precisely at the two roles where a shared blind spot is most dangerous.

**Why it's parked.** It's a second-vendor integration, not a tuning knob. This team lives entirely inside one harness: `Agent(subagent_type=…)`, Claude-tier model pins, an orchestrator model-override that only speaks Claude tiers, an exact cost hook priced from `model-rates.json` at Claude list rates, a dispatch guard, and a manifest. A non-Claude model cannot be a *subagent* here — it would arrive as an MCP tool / API call, which means a key and billing outside the subscription, a new pricing/accounting path the exact cost report doesn't have, and a critic that sits outside the subagent framework (no dispatch guard, no cost attribution, no manifest entry). That trades the team's best property — self-contained, shell-installable, exactly accountable — for maximal independence.

**Value-for-cost caveat.** The failure this design targets was caught by a human running a simple heuristic ("you're burying tech debt"). The *tells* do most of the work; whether the check runs at all with the right prompt is the bulk of the win. A Fable-critic-vs-Opus-architect split already captures most of the independence benefit at zero new architecture. Cross-vendor is a real but modest further increment against this specific failure mode, at a steep architectural price.

**Where it would plug in.** The same decision point as the Claude-only version: the orchestrator's model-override when it dispatches the spec critic (Section 3 of the decision-discipline design). A future version points that override at a cross-vendor critic via MCP instead of Fable — no change to the surrounding routing.

**Promotion trigger (2026-07-10 re-panel).** Newman's residual dissent on v2.1: the same-lineage detection paths may *correlate* rather than decorrelate, and the multi-path redundancy is a hypothesis, not a banked control. So this is no longer purely deferred — build it when either (i) a post-ship incident shows the same-lineage critic missed a stopped-short or un-enumerated consequential decision, or (ii) the raw-spec survey's recall proves insufficient in practice. Until then it stays parked, but the trigger is live.

---

## Team-wide decision discipline (all specialists)

**Raised:** 2026-07-10, during the decision-discipline design pass (scope question, option C).

**Idea.** Have *every* specialist internalize the two questions ("does this matter?" / "did I actually work it?"), with the orchestrator routing self-review vs. independent critic for any specialist's output — not just the architect's spec.

**Why it's attractive.** "Don't stop short" and "is this trivial" are instincts that apply to the builder, the ops agent, the researcher — anywhere a specialist makes a consequential call. The most consistent version of the discipline covers the whole team.

**Why it's parked.** It's the largest version of the change and the easiest to over-apply — it risks reintroducing exactly the over-process the Trivial tier and investigate-first amendments were written to prevent. The current pass targets where the failure actually happened (the architect's spec) and proves the pattern there first. Generalizing is a natural follow-up once the architect + spec-critic version has run in practice.

**Where it would plug in.** The shared two-questions vocabulary already lands in the agent files as self-contained prose (Approach A). Extending it means referencing that same vocabulary from other specialists' bodies and adding critic-trigger judgment for their outputs to the orchestrator's routing — an increment on the same foundation, not a rebuild.

---

## Cross-session dispatch serialization does not exist

**Found:** 2026-08-14, during a read-only forensic investigation of three Claude Code sessions that ran concurrently against one checkout of a different repository (`/Users/jay/claude/innovation-awards`); two of them integrated commits into the same shared `main` minutes apart. Nothing was lost, but only because one session's executor stopped when it hit a diverged history instead of forcing past it.

**What's broken.** `hooks/agent-team-dispatch-guard.sh` serializes the git-mutating roles by checking the *dispatching session's own transcript* for other in-flight dispatches to the same target. That transcript is private to one session. Two orchestrators each running this guard therefore each serialize their own dispatches perfectly while being completely blind to the other's — there is no cross-session lock of any kind.

**Evidence.** `hooks/agent-team-dispatch-guard.sh:21` — `readonly GIT_SERIALIZED_ROLES="builder executor deployer test-author"`, and the serialization does work within one session. The in-flight set is computed by `jq -rs` over `$TRANSCRIPT`, which is `.transcript_path` from the hook payload — the dispatching session's own transcript. `grep -rlnE "flock|lockfile|\.lock"` across `hooks/`, `agents/`, and `skills/` in this build returns no matches (reconfirmed while filing this entry).

**What a fix would have to establish.** Shared state outside any one session's transcript — a lock file, a shared registry keyed by target path, or equivalent — that a second concurrent orchestrator actually reads before dispatching, not a convention that silently assumes one orchestrator at a time.

---

## No gate protects the shared history pointer or the shared index

**Found:** 2026-08-14, same investigation.

**What's broken.** `hooks/agent-team-worktree-guard.sh` confines a builder's writes to its own declared worktree, and it did its job in the incident — it rejected `git -C <outside>` and no file edit collided. But it protects working files only. It has no notion of the shared `main` ref or the shared git index that two sessions in different worktrees of the same repository both write through at integration time, and it is wired for exactly one role.

**Evidence.** `hooks/agent-team-worktree-guard.sh:46` — `readonly POLICED_ROLES="builder"`; line 20 states "Only mutation is confined." The guard is dispatched only from `agents/builder.md`'s frontmatter hooks (three `PreToolUse` wirings, all `agent-team-worktree-guard.sh builder`, at `agents/builder.md:17,26,32`); it never runs for `executor`, `architect`, `scribe`, `ops`, `verifier`, `reviewer`, or `debugger`.

**What a fix would have to establish.** Protection for the object that is actually shared — the ref two sessions both advance and the index both sessions' integration steps touch — as a control distinct from, and in addition to, the per-worktree file confinement that already works correctly.

---

## The only globally registered dispatch check exits early for every role but builder

**Found:** 2026-08-14, same investigation.

**What's broken.** The one dispatch-time check registered globally for every Claude Code session on the machine, `~/.claude/hooks/agent-dispatch-lint.sh`, exits immediately for every subagent type except `builder`. Its own header already documents the gap it leaves: the workforce dispatch guard runs only inside the orchestrator agent's own frontmatter hooks, so a plain main session that dispatches anything other than a builder — including another orchestrator — gets no dispatch-time check at all.

**Evidence.** `~/.claude/hooks/agent-dispatch-lint.sh` line 44: `case "$TYPE" in` followed by `builder|agent-workforce:builder) ;; *) exit 0 ;; esac`. The file's own header states: "the workforce dispatch guard … runs only inside the orchestrator agent's own frontmatter hooks. A plain main session that dispatches a builder gets NO dispatch-time check." `grep -n "agent-team" ~/.claude/settings.json` returns nothing — the workforce guards are wired per-agent instead: `agents/orchestrator.md:16` wires `agent-team-dispatch-guard.sh` on `PreToolUse(Agent)`, and `agents/builder.md:17,26,32` wire `agent-team-worktree-guard.sh builder`.

**What a fix would have to establish.** A dispatch-time check that runs for every subagent type, in every session, regardless of which agent is doing the dispatching — not only builder dispatches launched from an orchestrator's own hooks.

---

## Non-builder roles may write the shared checkout with every gate approving

**Found:** 2026-08-14, same investigation.

**What's broken.** `docs/product/` falls inside the architect's write lane, and `architect` appears in neither `WORKTREE_REQUIRED_ROLES` nor `GIT_SERIALIZED_ROLES` nor `POLICED_ROLES`. In the incident an architect wrote a roughly 160 KB plan directly into the shared checkout of the other repository while a second session was working there, and no gate objected.

**Evidence.** `hooks/agent-team-worktree-guard.sh:46` (`readonly POLICED_ROLES="builder"`) and `hooks/agent-team-dispatch-guard.sh:21` (`readonly GIT_SERIALIZED_ROLES="builder executor deployer test-author"`) — `architect` is absent from both sets. `skills/project-policy/SKILL.md:25` states the workspace-isolation policy in builder-scoped terms ("every builder creates its own unique git worktree and works only inside it"); the policy's own wording does not reach any other role writing the shared checkout.

**What a fix would have to establish.** Either a workspace-isolation policy statement that actually covers every role capable of writing the shared checkout, or guards whose policed/serialized sets are derived from "can this role write files" rather than hand-enumerated to `builder` alone.

---

## The lane-refusal rule conflates naming a path with writing it, and makes a false refusal permanent

**Found:** 2026-08-14, same investigation.

**What's broken.** Once any specialist emits `WORKFORCE_REFUSAL: out-of-lane` for a path, the dispatch guard refuses every later dispatch whose prompt merely contains that path string as a substring — with no read-versus-write distinction. For a path in no declared lane, `lane_role_owner` returns empty and the guard falls back to declaring the builder its owner, so every other role is refused for merely naming it. In the incident a scribe declined `ISSUES.md`, and the guard then refused four separate strictly read-only dispatches in that session — reviewer, verifier, debugger, and executor — for naming that same file. Two of those are the workforce's own evidence-gathering roles for that file, and one (executor) is the role that must name the file to integrate it.

**Evidence.** `hooks/agent-team-dispatch-guard.sh:235` — `case "$PROMPT" in *"$refused_path"*) ;; *) continue ;; esac`, with `refused_path` extracted from the marker defined at line 33: `readonly REFUSAL_MARKER="WORKFORCE_REFUSAL: out-of-lane"`. `hooks/agent-team-lanes.json:2` describes itself as "Write lanes the workforce guards enforce" — a read-only dispatch is not the case this refusal mechanism is documented to cover. The guard's own comment at line 34 already records a prior instance of this exact failure mode: "On 2026-08-04 a lane guard defect refused an architect its own plan; the rule below then made that false refusal permanent routing law." The only release from a refusal is a human-authored override line.

**What a fix would have to establish.** A distinction between a dispatch that would write the refused path and one that only reads or names it, so that a correct refusal of write access does not become a standing block on every future mention of that path by roles that never write it.
