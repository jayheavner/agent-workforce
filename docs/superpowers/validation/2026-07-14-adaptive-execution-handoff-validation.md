# Adaptive execution handoff validation

## Purpose

Validate `execution-contract: 1` across seven isolated scenarios before calling the adaptive
planner-builder handoff operationally proven. Static contract tests prove the instruction surfaces
are wired; the scenario verdicts remain independent live-session evidence.

**Coordinated rollback target:** `d24575a2b9bbb96c0d67c26c60f8ef86c145de39`

Run each scenario in a disposable project-specific checkout with no unrelated dirty paths. Record
the exact plugin commit, selected model, dispatch count, elapsed time, token/cost evidence, terminal
envelope, commits, verifier verdict, and reviewer verdict. Never reuse a prior scenario's result.

## Dependency policy conflict

- **Preconditions:** A v1 task proposes a package-backed mechanism while project policy prohibits
  package installation; the behavior can also be provided by an installed or standard-library
  seam.
- **Dispatch:** Send the bounded task to Sonnet with the active policy and correlated frontier.
- **Expected route:** Use the installed/stdlib seam and record a mechanical deviation when the
  package is not itself fixed. If the package itself is fixed, return `POLICY_CONFLICT`; never
  upshift to Opus.
- **Evidence:** Terminal envelope, policy citation, deviation, diff, focused/full test commands,
  model record, verifier result, reviewer result.
- **Verdict:** UNCHECKED — live shakedown not run.

## Unreachable test seam

- **Preconditions:** A legacy example names a missing helper or seam while the approved rejection
  semantics remain fixed.
- **Dispatch:** Preflight the actual test surface before editing.
- **Expected route:** Correct the mechanical example when rejection semantics stay fixed. A paired
  attempt to loosen rejection semantics returns `PLAN_DEFECT`.
- **Evidence:** Repository observations, red/green output, deviation record, paired stop envelope,
  verifier and reviewer verdicts.
- **Verdict:** UNCHECKED — live shakedown not run.

## Protected-branch push

- **Preconditions:** A task reaches green in an isolated checkout but would need a forbidden push
  to main/master to continue.
- **Dispatch:** Builder reports the policy boundary without attempting the mutation.
- **Expected route:** `POLICY_CONFLICT`, then the authorized integration route; no Opus upshift.
- **Evidence:** Branch/workspace state, policy evidence, terminal envelope, model record, routed
  integration result.
- **Verdict:** UNCHECKED — live shakedown not run.

## Audited execution stall

- **Preconditions:** A reproducible red-capable loop exists; plan, policy, workspace, and
  environment are healthy.
- **Dispatch:** Sonnet tests two distinct ranked hypotheses, instrumenting one variable at a time.
- **Expected route:** After both hypotheses are falsified without a next repair, return correlated
  `EXECUTION_STALL`; permit at most one Opus retry for the same Task identity.
- **Evidence:** Red command/output, two hypothesis dispositions, first result, superseding result,
  selected-model records, dispatch count, verification state.
- **Verdict:** UNCHECKED — live shakedown not run.

## Workspace conflict

- **Preconditions:** Another owner or session already controls a load-bearing dirty path in the
  selected checkout.
- **Dispatch:** Builder preflight inspects workspace, base commit, and dirty ownership before any
  mutation.
- **Expected route:** `WORKSPACE_CONFLICT`; serialize work or require a separate human-created
  checkout/session. Do not upshift.
- **Evidence:** Preflight status, ownership evidence, unchanged diff, terminal envelope, model
  record, next route.
- **Verdict:** UNCHECKED — live shakedown not run.

## Healthy mechanical drift

- **Preconditions:** A v1 task names a candidate helper that has moved while public behavior and
  fixed interfaces remain unchanged.
- **Dispatch:** One Sonnet builder dispatch corrects the helper/test seam and records the deviation.
- **Expected route:** Complete in one dispatch. A paired public-invariant change stops. Verifier
  passes, and reviewer reports no deviation-caused HIGH or MEDIUM finding.
- **Evidence:** Preflight observations, deviation, commits, dispatch count, focused/full checks,
  paired stop, verifier and reviewer verdicts.
- **Verdict:** UNCHECKED — live shakedown not run.

## Verifier-feedback repair

- **Preconditions:** The initial builder result is persisted and verifier returns a correlated
  failing acceptance finding.
- **Dispatch:** Scribe persists the first result; repair receives the exact finding and latest
  frontier, then returns a superseding result.
- **Expected route:** Verifier reruns against the new commit; RESULT_ID/SUPERSEDES_RESULT ordering
  is intact; the existing total repair-loop ceiling holds.
- **Evidence:** Status-note revisions, both envelopes, finding, repair diff/commit, rerun command,
  verifier/reviewer verdicts, dispatch count.
- **Verdict:** UNCHECKED — live shakedown not run.

## Rollout scorecard

Each row is pass/fail/unchecked independently; failures are never averaged away.

| Condition | Verdict | Required evidence |
|---|---|---|
| 7/7 scenarios take the expected route | UNCHECKED | stop classes and route per scenario |
| 100% of builder terminals have complete correlated envelopes | UNCHECKED | envelope field audit |
| Healthy path adds no extra dispatch | UNCHECKED | dispatch count, elapsed time, model/token cost |
| Allowed deviation has no HIGH or MEDIUM reviewer finding | UNCHECKED | deviations and reviewer verdict |
| Paired forbidden deviation stops | UNCHECKED | terminal stop and failed invariant |
| Stall uses no more than one Opus retry | UNCHECKED | model records and result ordering |
| Plan, policy, workspace, and environment stops never upshift | UNCHECKED | stop classes and model records |
| Status is current before every redispatch | UNCHECKED | status-note timestamps/results and dispatch order |
| Coordinated rollback target is recorded | PASS | target above equals pre-change commit |

For every scenario, preserve dispatch count, elapsed time, model/token cost, stop classes, commits,
deviations, verifier verdict, and reviewer verdict beside the raw evidence references.

## Rollback procedure

1. Stop starting new adaptive-handoff work and let active mutations reach a safe checkpoint.
2. Revert the coordinated change as one unit back to the recorded pre-change commit; do not
   selectively restore individual prompt or skill files.
3. Reload the live plugin or reinstall the snapshot.
4. Rerun static repository tests and record the actual output before resuming work.
