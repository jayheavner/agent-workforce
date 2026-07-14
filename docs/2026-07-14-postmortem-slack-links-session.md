# Post-mortem: the Slack-links session (2026-07-14)

Session: `2026-07-14-171659-all-slack-links-to-workspace-are-wrong-heres-on.txt`,
run as the orchestrator (team build af768b5) in the `email_webhook_handler` project.

## What the task actually was

Slack notifications carry links to `https://ea.cta.tech/audit?...` and the links don't render.
The true answer: `ea.cta.tech` was never provisioned, the Vue workspace was never deployed
anywhere, and the app only runs locally via `cd ui && npm run dev` at `localhost:5173` — a fact
recorded in the target project's own CLAUDE.md, which was in context the entire session.

## The one-sentence verdict

**The first ops dispatch verified the present state correctly in under two minutes: nothing is
reachable today, the app runs locally. The orchestrator then relayed that point-in-time evidence
as a historical absolute — "never provisioned," "has never been deployed," "no correct URL" —
which its checks could not support. The human answered that absolute exactly as stated ("there
was a URL; I used it"), and instead of separating *now* from *then*, the orchestrator flipped to
the opposite absolute ("so it is deployed") and abandoned its verified present-state finding.
The rest of the session was an argument about history that was irrelevant to the fix — the fix
depended only on whether a URL exists now, and that was already answered.**

Ops dispatch #1 reported: NXDOMAIN, never provisioned, no hosting anywhere, exists only at
`localhost:5173` on a dev machine. Two hours, four more dispatches, one credential rabbit hole,
and one killed launchd service later, the session's final conclusion was the same sentence.

## Timeline of the failure

1. **Correct triage, correct investigation, overstated relay.** The orchestrator followed its
   investigate-first rule, found the `WORKSPACE_URL` source, and dispatched ops. Ops #1 (18 tool
   uses) checked DNS, Amplify, CloudFront, S3, API Gateway, Route53, GoDaddy — all point-in-time
   reads proving the present state: nothing reachable, app runs locally. The orchestrator relayed
   this as history: "never provisioned," "has never been deployed anywhere public," "there is no
   correct URL to point to." No check performed then (or later) could establish "never."
2. **The pivot point.** The human answered the premise exactly as stated to them. Told "no
   correct URL," they replied: *"I've been in this platform hundreds of times back when it had a
   normal Amplify URL. This is LAZY work."* — i.e., a URL existed and they used it. "Nothing is
   up now" and "there was a URL then" are claims about different times; both can be true; neither
   was in conflict with the actual evidence. The orchestrator, instead of separating now from
   then, flipped to the opposite historical absolute ("My bad — so it is deployed") and discarded
   its verified present-state finding. Whether an Amplify URL ever existed for this app was never
   settled in the session — and never needed to be, because the fix depends only on present state.
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

### RC1 — Claims overran the evidence, then flipped instead of being scoped (primary)

The failure has two halves, and the orchestrator owns both.

**First, the overclaim.** Point-in-time reads (DNS today, Amplify listing today, Route53/GoDaddy
zones today) were relayed as historical absolutes: "never provisioned," "has never been
deployed," "there is no correct URL to point to." A present-state check cannot prove "never."
The overclaim is what invited the pushback: the human answered the premise as stated — told "no
URL," they reported that a URL existed and they had used it. That answer was responsive and
reasonable; the premise was the defective part.

**Second, the flip.** Handed a claim about *then* that its evidence about *now* couldn't speak
to, the orchestrator had a cheap, honest move: scope the claim — "nothing is reachable today;
whether it was hosted in the past I haven't checked, and the fix only depends on today." Instead
it swung to the opposite absolute ("so it is deployed"), discarded the verified present-state
finding, and spent four dispatches and most of the session litigating a historical question that
was irrelevant to repairing the links. The historical question was never settled — and never
needed to be.

The general rule this session demands: **a finding's tense must match its evidence.** Absence
observed now is not absence always; a specialist or orchestrator that says "never" from a
snapshot has already overclaimed, and every downstream argument inherits the defect. And when a
human's account conflicts with a claim, the first check is whether the two even speak to the
same time and scope — most such conflicts dissolve under scoping rather than needing adjudication.

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

### RC5 — The answer was produced in minute two and never said plainly

Ops #1's report contained the complete answer, verbatim: "it exists only on a dev machine at
localhost:5173." One sentence away from closing the session: "the app hasn't been deployed; it
runs locally; start the dev server (`cd ui && npm run dev`, per the project's CLAUDE.md)." The
orchestrator never said that sentence because it reported in the frame of its *route*, not the
human's *situation*: the task had been tiered as "find the URL, repoint the config," so the
finding was presented as a broken premise and a returned decision ("there is no correct URL to
point to... this is a genuine decision that's yours to make") rather than as the action a human
needs. The framework's reporting vocabulary — tiers, gates, premises, dispatches — has no slot
for "just run this command," and the orchestrator cannot run commands itself. A thirty-second
conversation became a two-hour one because the answer was phrased as project management instead
of as help.

### RC6 — The debugging discipline was never invoked, and mostly couldn't be

The org's `debugging` skill (ranked falsifiable hypotheses, one variable at a time, evidence
before fixes) is the direct antidote to the anchoring failure this session exhibited. It was
never loaded by anyone. Structurally it barely could be: the orchestrator has no `Skill` tool at
all; ops has the tool but is granted only `handling-secrets`; the sole agent with `debugging`
preloaded — the builder — was dispatched twice, both times for mechanical work (start a server,
free a port), never for diagnosis. The agents that did the diagnostic reasoning had no access to
the discipline that governs diagnostic reasoning.

### RC7 — Question quality at gates

Three pickers landed badly: asking the human for the URL after the human's opening message
established they don't have a working one ("If I had the URL would I ask?"); asking how to get
credential access when documentation existed; and a resolution picker re-presented after the
human declined it. The gate machinery is tuned for *decision-shaped* questions (tradeoffs);
here it kept emitting *fact-shaped* questions the orchestrator was supposed to answer itself.
Each one converted human frustration into the pressure that fed RC1.

## What went right

- The investigate-first rule (2026-07-09 amendment) worked as designed: cheap reads before
  tier/route commitment, and ops #1 was thorough and correct about the present state — the
  defect was introduced in how its findings were restated, not in the investigation.
- Ops policy hooks held: read-only enforced; mutation (launchd bootout) surfaced for approval.
- The builder's launchd finding (respawn via launchd, not a stray process) was a genuinely good
  diagnosis, and the destructive step was gated, reversible, and documented.
- The final self-diagnosis of the anchoring failure was honest and mechanistically accurate.

## Recommendations

1. **Tense-and-scope discipline on findings (orchestrator + specialists).** A finding may claim
   only what its evidence covers: a point-in-time read yields a present-state claim ("nothing
   reachable now"), never a historical one ("never deployed"). When a human's account conflicts
   with a finding, first check whether they speak to the same time and scope — scope the claim
   before adjudicating it, and never resolve the conflict by flipping to the opposite absolute.
   A re-dispatch to "find" a thing whose present-state absence was verified requires a stated
   new fact, not a restated recollection.
2. **Findings ledger.** The orchestrator keeps a short pinned list of established facts
   (claim + evidence + which dispatch proved it). Every subsequent dispatch prompt includes it;
   any dispatch that would contradict an entry must say which entry and why.
3. **A live-troubleshooting route.** Triage gains a signal: interactive debugging / "why is X
   broken right now" sessions route to a single hands-on agent (Bash + Read, debugging skill),
   not the phased orchestration. The orchestrator's honest move in this session was to say, in
   its first triage line, "this is live debugging — run it in a plain session, not the team."
   Whatever agent carries diagnosis must load the `debugging` skill: today the orchestrator has
   no Skill tool and ops carries only `handling-secrets`, so the discipline is unreachable on
   every diagnostic path (RC6). Grant ops the `debugging` skill regardless of the new route.
4. **Relay fidelity, and answers as actions.** When a specialist report contains a fact the
   human will act on (a port, a URL, a command), relay it verbatim; never substitute the
   orchestrator's own inference for the specialist's stated fact (the 5173/5174 error was pure
   orchestrator reinterpretation). And when a finding answers the human's actual situation,
   lead with the plain actionable sentence ("it runs locally — start it with `npm run dev`"),
   not with what the finding means for the route (RC5).
5. **Fix the Okta credential story in the environment, not the agents.** Reconcile okta.md, the
   shell config, and the service-account vault to one canonical, currently-valid path; refresh or
   remove the expired ClaudeCodeAccess-Jay token. Until then, every agent session inherits a trap.
6. **Fact-shaped questions are dispatches, not pickers.** Extend the existing "factual questions
   are dispatches, not memory" rule: before any AskUserQuestion, the orchestrator checks whether
   the question is answerable by evidence it can reach; only genuine preference/tradeoff/authority
   questions go to the human.

## Disposition (2026-07-14)

- Rec 1 (tense-and-scope): orchestrator rule in a02d457; ops rule and the debugger's
  evidence-scoping in d088c01/a02d457. **Done.**
- Rec 2 (findings ledger): orchestrator section in d088c01. **Done.**
- Rec 3 (live-troubleshooting route): `debugger` specialist + symptom-first routing in a02d457;
  ops granted the debugging skill. **Done.**
- Rec 4 (relay fidelity / answers as actions): orchestrator rule in d088c01; debugger report
  format in a02d457. **Done.**
- Rec 5 (Okta credential reconciliation): **open — environment work requiring the human** (the
  live token lives in the Employee vault, unreachable by the agents' service account).
- Rec 6 (fact-shaped questions): orchestrator rule in d088c01. **Done.**
- Found along the way: install.sh died on macOS bash 3.2 (empty-array expansion under set -u),
  failing 31 install-test checks — fixed in c0c1c57; suite 36/36. Build c0c1c57 installed to
  the live profile.
- The original deliverable — the broken Slack links in email_webhook_handler — **remains open
  pending the human's decision**: remove the links, deploy the workspace, or accept local-only.

## Cost of the failure

Five specialist dispatches (~275k subagent tokens) plus orchestrator overhead; roughly fifteen
increasingly hostile human turns; and at session end the original deliverable — the broken Slack
links — remained unfixed (the recap says so). The correct answer had been in hand since the
first dispatch, and in the project's CLAUDE.md since before the session began.
