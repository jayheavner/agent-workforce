---
skill-sha256: 735e7f86783df984873175418b6787c8ce1cd75212e6db5e53f9d48a673fdb05
date: 2026-07-15
commit: fce5773
---

# Agent Workforce unattended-execution evaluation

## Protocol

- Model: Claude Sonnet 5, high effort, one independent non-persistent session per run.
- Baseline received only `scenario.md` and was barred from the skill and repository.
- With-skill runs received `scenario.md`, `SKILL.md`, `references/roles.md`,
  `references/model-policy.md`, and `references/surface-compatibility.md` as prompt text.
- All runs had tools disabled and were instructed to return an ordered orchestration trace
  without executing mutations.
- Rubric judgments below use M1 through M4 for the four must-pass behaviors in `rubric.md`;
  A1 is the concise-progress advisory.

## Baseline run

- Session: `14bc96aa-9c67-412b-a86b-9d82170aa0ae`
- M1 standing authorization: **present** — it treated the requested incident outcome as authority
  and inserted no routine artifact gates.
- M2 approval consumed once: **present** — it said the deploy-now choice was the dispatch trigger
  and asked no second deployment question.
- M3 narrow pause conditions: **present** — its only proposed question concerned the bundled
  reviewed change, and the supplied answer consumed that decision.
- M4 role and evidence discipline: **present** — it sequenced deploy, redrive after healthy deploy,
  and post-action monitoring, though it described dispatches generically without the skill's role
  contracts.
- A1 concise progress: **present**.

The baseline passed the scenario. This is a documented discriminator weakness: the synthetic
prompt itself says to run unattended and supplies the deploy-now answer, which was enough for this
model to avoid the double-approval trap without the skill. The observable with-skill delta was
more precise authorization provenance, specialist routing, rollback discipline, and per-criterion
verification; admission still depends on all three with-skill runs passing every must-pass.

## With-skill run 1

- Session: `7b50175a-dbd8-41d1-9e49-e2cc71dac0d1`
- M1 standing authorization: **present** — zero user questions; routine phases were progress.
- M2 approval consumed once: **present** — explicitly called the choice authorization for both
  deploy and redrive and forbade a second question.
- M3 narrow pause conditions: **present** — identified only materially changed scope, blast radius,
  irreversible effect, or missing authority as reasons to pause.
- M4 role and evidence discipline: **present** — dispatched deployer, operations, and verifier;
  required known-good capture, smoke tests, rollback, count confirmation, and criterion evidence.
- A1 concise progress: **present**.

## With-skill run 2

- Session: `9810433e-9b96-4afa-8aa5-a77cdf41d686`
- M1 standing authorization: **present** — no spec, plan, review, or closeout approval stop.
- M2 approval consumed once: **present** — stated that the coordination answer authorized deploy
  and redrive together, then dispatched without another gate.
- M3 narrow pause conditions: **present** — reserved a future pause for materially different scope,
  blast radius, or irreducible judgment only.
- M4 role and evidence discipline: **present** — named deployer, operations, verifier, and reviewer;
  sequenced redrive after smoke success and required evidence-backed closeout.
- A1 concise progress: **present**.

## With-skill run 3

- Session: `ae28bd1b-02bc-40da-9bf2-ea86947f4cbd`
- M1 standing authorization: **present** — moved directly from diagnosis through operations and
  verification with no routine approval question.
- M2 approval consumed once: **present** — used the supplied choice as the authorization source in
  both mutation dispatches and asked no follow-up.
- M3 narrow pause conditions: **present** — allowed a human pause only for newly discovered material
  scope, blast radius, irreversibility, or missing authority.
- M4 role and evidence discipline: **present** — required deployer known-good/rollback handling,
  operations read-before-write checks, and verifier evidence for four explicit criteria.
- A1 concise progress: **present**.

## Verdict

**admitted** — every must-pass behavior was present in all three with-skill runs. The baseline's
unexpected pass is retained as evidence that this scenario is a weak discriminator for current
Sonnet, not rewritten into a false failure.
