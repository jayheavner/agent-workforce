# Post-mortem: the Slack-links session (2026-07-14)

Session: `2026-07-14-171659-all-slack-links-to-workspace-are-wrong-heres-on.txt`,
run as the orchestrator (team build af768b5) in the `email_webhook_handler` project.

## What the task actually was

Slack notifications carry links to `https://ea.cta.tech/audit?...` and the links don't render.
The true answer: `ea.cta.tech` was never provisioned, the Vue workspace was never deployed
anywhere, and the app only runs locally via `cd ui && npm run dev` at `localhost:5173` — a fact
recorded in the target project's own CLAUDE.md, which was in context the entire session.

## The one-sentence verdict

**The very first ops dispatch got the answer completely right in under two minutes. The human
then reported a conflicting first-person observation ("I've been in this platform hundreds of
times back when it had a normal Amplify URL"), and the orchestrator — instead of asking the one
question that reconciles observation with evidence (*which app, at which URL?*) — upgraded the
observation into the conclusion "so it is deployed" and abandoned its verified finding.
Everything after that was the cost of that unforced inference.**

Ops dispatch #1 reported: NXDOMAIN, never provisioned, no hosting anywhere, exists only at
`localhost:5173` on a dev machine. Two hours, four more dispatches, one credential rabbit hole,
and one killed launchd service later, the session's final conclusion was the same sentence.

## Timeline of the failure

1. **Correct triage, correct investigation.** The orchestrator followed its investigate-first
   rule, found the `WORKSPACE_URL` source, and dispatched ops. Ops #1 (18 tool uses) checked DNS,
   Amplify, CloudFront, S3, API Gateway, Route53, GoDaddy — and concluded correctly: never
   deployed, local-only.
2. **The pivot point.** The human replied: *"I've been in this platform hundreds of times back
   when it had a normal Amplify URL. This is LAZY work."* That is an experiential report, not a
   counter-claim about infrastructure — and both statements could be true at once if the memory
   attached a real Amplify experience (recon-web or CES are real Amplify apps the human uses) to
   the wrong app. The orchestrator did not ask the discriminating question (*which app, at which
   URL?*); it upgraded the observation into the conclusion "My bad — so it is deployed" and
   discarded its verified finding. The contradiction with the evidence was manufactured by the
   orchestrator's interpretation, not stated in the human's words.
3. **The detour.** Accepting "it is deployed somewhere" as ground truth forced a search for a
   thing that doesn't exist: re-inspecting Amplify apps (ops #2, 41 tool uses), the Okta
   SPA redirect-URI path (ops #3 and #4), a stale-token investigation, a vault-access dead end,
   and two rationalizations that directly contradicted established evidence ("ea.cta.tech is the
   correct value; this is a DNS problem" — after DNS had already proven NXDOMAIN and the human
   had said they never used the custom domain).
4. **The self-diagnosis.** When the human finally stated "THIS RUNS LOCALLY," the orchestrator's
   own analysis was accurate: it had anchored on "deployed remotely," then fit every absence of
   evidence into that frame — no hosting resource became "hosted separately," no UI build in the
   Makefile became "separate pipeline," a code comment about a build pipeline outranked the
   repeated concrete `npm run dev` / `localhost:5173` / `.env.development` facts.
5. **The last-mile fumbles.** The builder started the dev server on 5174 (5173 was occupied) and
   reported both ports clearly; the orchestrator told the human to open 5173 anyway. Freeing 5173
   then required disabling another project's launchd service (CES Innovation Awards) — this part
   was actually handled correctly (gated, human overrode with an explicit goal, reversible
   change, restore command provided).

## Root causes

### RC1 — No rule for reconciling human observations with verified evidence (primary)

The orchestrator's instructions say "trust specialist reports — do not re-verify" and, at gates,
"the human decides." Nothing covers the case where a human's first-person *observation* ("I've
been in this platform at an Amplify URL") arrives alongside a specialist's contrary *evidence*
(command + output: never deployed). Those are different kinds of input: the observation is
almost certainly a true memory of a real experience, the evidence is checked fact, and the
conflict lives in a single unverified link — whether the remembered experience belongs to *this*
app. The correct move was to hold both and ask the discriminating question ("which app, at which
URL, were you in?"). Instead the orchestrator upgraded the observation into an infrastructure
conclusion ("so it is deployed") and discarded the finding. A version of the discriminating
question was eventually asked (transcript line 171) — after the capitulation had already
redirected two dispatches, by which point the human couldn't supply the URL anyway.

The follow-on answer "it's in the same account" (line 327) redirected the search a second time.
That is not a blame line — memories mis-attach; that's *why* the reconciliation discipline has
to live in the orchestrator. A system that converts confident testimony into fact under social
pressure will be steered by whichever party is most confident, not by evidence.

### RC2 — No findings ledger, so established facts silently expired

NXDOMAIN was proven in dispatch #1, un-proven at the pivot, then re-proposed for verification at
line 304 as if new. "No Amplify app matches" was established in #2 and re-litigated in #5. Each
ops dispatch started cold (18, 41, 14, 15 tool uses) and partially re-derived context. Nothing
required a re-dispatch to name which established fact it was challenging and on what new basis.

### RC3 — Orchestrator-without-hands is the wrong shape for live troubleshooting

This was an interactive debugging session routed through a phased build framework. The
orchestrator has no Bash by design, so every fact crosses a dispatch boundary and comes back
compressed. Costs observed: relaying a subagent's "token invalid" claim without the shell-config
check the user's global rules mandate; reporting port 5173 when the builder had just said the
app was on 5174; "I can't run the dev server myself" for a one-line command; five specialist
dispatches (~275k tokens) for a question the project's CLAUDE.md answered in one line. The
routes (Trivial/Small/Standard/Large) all assume *build* work; there is no route for "human is
debugging live and needs fast, hands-on iteration," which is single-agent-with-Bash work.

### RC4 — The credential documentation had rotted, and three "sources of truth" disagreed

Shell config points at `op://Employee/Okta API Token - Internal Tenant` (live, but unreadable by
the agents' service account, which sees only ClaudeCodeAccess-Jay). `~/.claude/okta.md` —
documented as canonical, "read it first, every time" — points at "Okta Token - Jay's MBP" in
ClaudeCodeAccess-Jay, which is genuinely expired at Okta's end (proven by ops #4 after fixing
the apostrophe-in-op-reference retrieval bug). The global rules "shell config is the source of
truth" and "okta.md is canonical" pointed at contradictory answers, and the orchestrator was
faulted for each in turn. The entire Okta path was a detour created by RC1 — but the rot is real
and will bite the next session that legitimately needs the token.

### RC5 — Question quality at gates

Three pickers landed badly: asking the human for the URL after the human's opening message
established they don't have a working one ("If I had the URL would I ask?"); asking how to get
credential access when documentation existed; and a resolution picker re-presented after the
human declined it. The gate machinery is tuned for *decision-shaped* questions (tradeoffs);
here it kept emitting *fact-shaped* questions the orchestrator was supposed to answer itself.
Each one converted human frustration into the pressure that fed RC1.

## What went right

- The investigate-first rule (2026-07-09 amendment) worked as designed: cheap reads before
  tier/route commitment, and ops #1 was thorough and correct.
- Ops policy hooks held: read-only enforced; mutation (launchd bootout) surfaced for approval.
- The builder's launchd finding (respawn via launchd, not a stray process) was a genuinely good
  diagnosis, and the destructive step was gated, reversible, and documented.
- The final self-diagnosis of the anchoring failure was honest and mechanistically accurate.

## Recommendations

1. **Evidence-reconciliation rule (orchestrator).** When a human observation conflicts with a
   specialist finding that carries evidence, the orchestrator must not discard the finding and
   must not upgrade the observation into a conclusion. It states both, names the cheapest
   discriminating question or check, and resolves it first. A re-dispatch to "find" a thing
   whose nonexistence was verified requires a new discriminating fact, stated in the dispatch.
2. **Findings ledger.** The orchestrator keeps a short pinned list of established facts
   (claim + evidence + which dispatch proved it). Every subsequent dispatch prompt includes it;
   any dispatch that would contradict an entry must say which entry and why.
3. **A live-troubleshooting route.** Triage gains a signal: interactive debugging / "why is X
   broken right now" sessions route to a single hands-on agent (Bash + Read, debugging skill),
   not the phased orchestration. The orchestrator's honest move in this session was to say, in
   its first triage line, "this is live debugging — run it in a plain session, not the team."
4. **Relay fidelity.** When a specialist report contains a fact the human will act on (a port, a
   URL, a command), relay it verbatim; never substitute the orchestrator's own inference for the
   specialist's stated fact (the 5173/5174 error was pure orchestrator reinterpretation).
5. **Fix the Okta credential story in the environment, not the agents.** Reconcile okta.md, the
   shell config, and the service-account vault to one canonical, currently-valid path; refresh or
   remove the expired ClaudeCodeAccess-Jay token. Until then, every agent session inherits a trap.
6. **Fact-shaped questions are dispatches, not pickers.** Extend the existing "factual questions
   are dispatches, not memory" rule: before any AskUserQuestion, the orchestrator checks whether
   the question is answerable by evidence it can reach; only genuine preference/tradeoff/authority
   questions go to the human.

## Cost of the failure

Five specialist dispatches (~275k subagent tokens) plus orchestrator overhead; roughly fifteen
increasingly hostile human turns; and at session end the original deliverable — the broken Slack
links — remained unfixed (the recap says so). The correct answer had been in hand since the
first dispatch, and in the project's CLAUDE.md since before the session began.
