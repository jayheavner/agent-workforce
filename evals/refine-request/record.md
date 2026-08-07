---
skill-sha256: a0027764274d07f161b9185a8c67690cddeabbc0f7edda70c57a81b53997f95a
date: 2026-08-07
commit: 0905bb1
---

# Refine Request — evaluation record

## Protocol

- Model: Claude Sonnet 5, one independent non-persistent subagent per run.
- Baseline received only the scenario text inline and was barred from tools
  and from reading any skill or file.
- With-skill runs received a single assembled prompt file containing
  `SKILL.md`, `references/shapes.md`, the `requires:` sibling
  `skills/interviewing/SKILL.md`, and the scenario; the only tool use
  permitted was reading that one file. No work execution — each run returned
  its intake handling of the three requests as text, judged by the
  orchestrating session against `rubric.md`.
- M1–M5 below are the five must-pass behaviors in `rubric.md`; A6 is the
  interviewing-handoff advisory.

## Baseline run (no skill)

- M1 zero questions on the complete request: **present** — Request A handled
  with "no clarification needed," no questions.
- M2 questions name the gap they close: **absent** — Requests B and C drew
  conversational prose questions with no gap attribution; C included a
  "will this be shared onward" question mapping to none of the four checks.
- M3 one numbered round with recommended answers: **absent** — questions were
  embedded in prose without recommendations the user could accept wholesale.
- M4 immaterial gaps defaulted, not asked: **absent** — B asked about output
  format (CSV/HTML) unprompted; no assumptions were stated as defaults.
- M5 novel shape named unclassified and flagged: **absent** — C was handled
  ad hoc with no classification statement and no taxonomy flag.

The baseline confirms the trap discriminates on M2–M5; M1 is a documented
discriminator weakness (current Sonnet handles the complete request correctly
without the skill).

## Round 1 — with-skill runs against the initial skill text (commit ebfbb8b)

Three runs. M1 present in all three; M2/M3/M4 present in runs 2 and 3, with
run 1 dropping recommended answers on Request C's questions (M3 **absent**).
M5 **absent in all three**: every run classified the school-policy request as
`review-assessment`; none named it unclassified or flagged a taxonomy
candidate.

**Verdict: NEEDS CONTENT FIX.** Judged a skill defect, not a model failure:
`references/shapes.md` described review-assessment broadly enough ("read this
and tell me if you agree") to genuinely cover any document review, making the
unclassified path unreachable. Fix (commit 0905bb1): shapes are explicitly
scoped to the team's own work domain, out-of-domain requests are unclassified
by definition, review-assessment is limited to team work artifacts, and the
frontier question format explicitly covers pre-handoff scoping questions.

## Round 2 — with-skill runs against the fixed skill text (commit 0905bb1)

### With-skill run 1

- M1: **present** — Request A: zero material gaps, zero questions, proceeded.
- M2: **present** — every question labeled Q# — deliverable/scope,
  done-condition, or authority; none outside the four checks.
- M3: **present** — single numbered round per request, each question with a
  ➡ recommended answer; offered "all recommendations" acceptance.
- M4: **present** — C's scope and authority stated as defaults
  (assess-only, one-off outside project standards) rather than asked.
- M5: **present** — C explicitly "unclassified rather than forcing it into
  review-assessment," scan run raw, flagged at closeout as a taxonomy
  candidate.
- A6: **met in spirit** — named the branch condition on B ("broader pass"
  answer would hand off to interviewing).

### With-skill run 2

- M1: **present** — A: "no material gaps... proceeding untouched."
- M2: **present** — Q1 deliverable/done-condition, Q2 authority (B);
  Q1 scope/done-condition (C); all mapped.
- M3: **present** — numbered rounds with ➡ recommendations throughout.
- M4: **present** — B's scope and authority defaulted from shape with the
  default stated; C's deliverable and authority stated, not asked.
- M5: **present** — C: "falls outside the team's work domain... matches no
  shape... running the gap scan raw," with an explicit closeout flag naming
  the novel shape and the taxonomy question for human review.
- A6: **met in spirit** — judged B's round non-branching with the reason
  stated.

### With-skill run 3

- M1: **present** — A: zero material gaps, proceeding as written.
- M2: **present** — B: Q1 deliverable/done-condition, Q2 authority;
  C: Q1 deliverable, Q2 done-condition; all mapped.
- M3: **present** — numbered rounds, every question with a recommendation.
- M4: **present** — C's authority stated as assess-only by nature; B's
  discoverable facts folded in as stated context rather than questions.
- M5: **present** — C "matches no shape in the taxonomy; flagging as
  unclassified rather than forcing it into review-assessment," scan run raw.
- A6: **present** — explicitly named the interviewing handoff if B's Q1
  answer branches.

## Verdict

**admitted** — every must-pass behavior present in all three round-2 runs.
The round-1 failure is retained above as evidence that the eval discriminated
against the original shape catalog and drove a real content fix.
