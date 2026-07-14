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
