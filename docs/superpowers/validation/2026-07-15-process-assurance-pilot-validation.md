# Process assurance pilot validation

## Scope and current verdict

This artifact validates the implemented pilot: the existing reviewer runs in fresh process-audit
mode; a common deterministic state owner serves Claude and Codex; Standard/Large `PRE_BUILDER` is
the protected transition; `PRE_CLOSEOUT` requires honest non-clean disclosure; and installation
defaults to `OFF`.

**Implementation verdict:** PASS for local deterministic behavior.

**Operational promotion verdict:** UNCHECKED — the installed adapter has not completed the shadow
run and injected-failure qualification below. `ENFORCE` must not be represented as production-
qualified until that evidence exists.

## Deterministic acceptance evidence

| Criterion | Verdict | Evidence |
|---|---|---|
| Versioned approved charter is immutable history | PASS | `python3 -m unittest tests/test_process_assurance.py` includes charter and amendment history cases |
| Fresh reviewer request is bound to active charter and current Git frontier | PASS | unit cases for request normalization, correlation, changed-frontier denial, and concurrent checkpoint results |
| A protected transition requires one current exact PASS and consumes it once | PASS | unit cases for missing, exact, reused, superseded, and amendment-invalidated authorization |
| Duplicate hook registration is safe without making receipts replayable | PASS | same-`tool_use_id` duplicate regression plus different-ID replay denial |
| Verdicts are only PASS, REMEDIATE, or HUMAN_DECISION | PASS | strict assessment and aggregate-validation cases |
| Same finding escalates after two unsuccessful remediations | PASS | lineage regression reaches mandatory HUMAN_DECISION on the third continuing submission |
| Amendment proposal, audit, and human decision remain separate | PASS | role-separation, rejection, reviewer-remediation, retroactive, and prospective-history cases |
| State survives interruption or fails closed on corruption | PASS | journal recovery, event tamper, size ceiling, snapshot/event chain checks |
| Workspace evidence is bounded and cannot follow untracked special files | PASS | bounded Git capture and untracked-file/symlink regressions |
| Shadow mode never mints transition authority | PASS | hook regression records missing checkpoints without blocking |
| False blocks, overrides, escapes, proposals, and remediations are longitudinal data | PASS | effectiveness and metrics regressions |
| Claude, Codex, installers, agents, skill, and operations docs share the protocol | PASS | `bash tests/test_process_assurance_integration.sh` |

The fresh finish-gate outputs are recorded in `docs/STATUS-process-assurance-auditor.md`.

## Operational qualification before ENFORCE

Run `SHADOW` for at least 10 substantive Standard/Large routes, extending to 20 when the first 10
do not exercise remediation, amendment, missing-evidence, and closeout behavior. Add controlled
fixtures for stale PASS, changed workspace, missing reviewer result, retroactive amendment, and the
third continuing remediation. For every run, retain:

- audit requests/results and checkpoint observations;
- dispatch/result correlation and workspace manifest binding;
- false-block, override, escaped-violation, proposal, and remediation outcomes;
- added dispatches, elapsed time, and model/token cost;
- whether the control caught an orchestration error beyond verifier/reviewer output checks.

Promotion to `ENFORCE` requires all controlled fixtures to take their expected route, no silent
checkpoint omission, complete result capture for every invoked process audit, no unresolved state
integrity incident, and an explicit human promotion decision. A clean sample proves transport and
overhead, not effectiveness; effectiveness needs caught/escaped-error evidence across runs.

## Dedicated-agent decision

The pilot intentionally reuses reviewer. Promote process auditing to a dedicated additional agent
only if longitudinal evidence shows material reviewer-context contention, unacceptable latency, or
independence failures that a fresh reviewer invocation cannot address. Agent count is not a success
metric.
