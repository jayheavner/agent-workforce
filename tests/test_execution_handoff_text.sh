#!/usr/bin/env bash
# Static contract checks for the adaptive planner-builder execution handoff.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PASS=0
FAIL=0

expect_grep() {
  if grep -qF -- "$2" "$1"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n' "$3"
  fi
}

expect_absent() {
  if grep -qF -- "$2" "$1"; then
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n' "$3"
  else
    PASS=$((PASS + 1))
  fi
}

# T1 — versioned plan producer and three-perspective review
expect_grep skills/planning/SKILL.md 'execution-contract: 1' 'planning lacks contract version'
for heading in 'Task identity' 'Outcome' 'Acceptance mapping' 'Files and responsibilities' \
  'Interfaces and invariants' 'Executable examples' 'Preflight checks' \
  'TDD and verification contract' 'Executor discretion' 'Escalation triggers' 'Commit intent'; do
  expect_grep skills/planning/SKILL.md "### $heading" "planning contains $heading"
done
expect_absent skills/planning/SKILL.md 'complete code in every step' \
  'planning still requires complete implementation code'
expect_absent skills/planning/SKILL.md 'one action each (2–5 minutes)' \
  'planning still requires recipe-size steps'
expect_grep agents/architect.md 'verified repository facts' 'architect distinguishes verified facts'
expect_grep agents/architect.md 'builder-preflight hypotheses' 'architect labels runtime hypotheses'
expect_grep agents/architect.md '**Architect intent:**' 'architect reviews intent'
expect_grep agents/architect.md '**Builder feasibility:**' 'architect reviews feasibility'
expect_grep agents/architect.md '**Verifier observability:**' 'architect reviews observability'

# T2 — builder contract consumption and typed terminal result
expect_grep agents/builder.md '## Contract consumption' 'builder lacks contract consumption rules'
expect_grep agents/builder.md '## Preflight before edits' 'builder lacks preflight'
for field in 'RESULT_STATUS:' 'STOP_CLASS:' 'RESULT_ID:' 'SUPERSEDES_RESULT:' \
  'PLAN_PATH:' 'TASK_ID:' 'CONTRACT_VERSION:' 'WORKSPACE:' 'BASE_COMMIT:' \
  'CURRENT_COMMIT:' 'DIRTY_PATHS:' 'FAILED_INVARIANT:' 'EVIDENCE:' \
  'HYPOTHESES:' 'VERIFICATION_PROVEN:' 'VERIFICATION_UNRUN:' 'RECOMMENDED_ROUTE:'; do
  expect_grep agents/builder.md "$field" "builder result carries $field"
done
for class in PLAN_DEFECT POLICY_CONFLICT ENVIRONMENT WORKSPACE_CONFLICT \
  AUTHORITY_REQUIRED PRODUCT_DECISION EXECUTION_STALL; do
  expect_grep agents/builder.md "$class" "builder defines $class"
done
expect_absent agents/builder.md 'MODEL_LIMIT' 'builder has blame-bearing model limit'
expect_grep agents/builder.md 'two distinct hypotheses' 'builder uses falsifiable no-progress rule'
expect_grep agents/builder.md 'package installs, file reorganization, and scaffolding proceed' \
  'builder preserves standing authorization for planned in-scope mutations'
expect_absent agents/builder.md 'no package installation' \
  'builder reintroduced a blanket package-install prohibition'

# T3 — orchestrator validation, routing, and model selection
expect_grep agents/orchestrator.md '## Execution contracts and builder results' \
  'orchestrator lacks execution result routing'
for class in PLAN_DEFECT POLICY_CONFLICT ENVIRONMENT WORKSPACE_CONFLICT \
  AUTHORITY_REQUIRED PRODUCT_DECISION EXECUTION_STALL; do
  expect_grep agents/orchestrator.md "$class" "orchestrator routes $class"
done
expect_grep agents/orchestrator.md 'Sonnet is eligible only when all are true' \
  'orchestrator lacks all-of Sonnet eligibility'
expect_grep agents/orchestrator.md 'An initial Opus dispatch is required when any one is true' \
  'orchestrator lacks any-one Opus triggers'
expect_grep agents/orchestrator.md 'Task length alone never triggers Opus' \
  'orchestrator prices by task length'
expect_grep agents/orchestrator.md 'at most one Opus retry per Task identity' \
  'orchestrator lacks stall retry cap'
expect_grep agents/orchestrator.md 'before any repair or resumed builder dispatch' \
  'orchestrator does not persist status before redispatch'
expect_absent agents/orchestrator.md 'Upshift the builder to `opus` for the second loop.' \
  'orchestrator retains unconditional second-loop upshift'

# T4 — persistence and independent downstream consumers
expect_grep agents/scribe.md 'every builder dispatch ends' 'scribe does not persist all terminal dispatches'
expect_grep agents/scribe.md 'RESULT_ID' 'scribe does not preserve result ordering'
expect_grep skills/handing-off/SKILL.md 'Plan path plus Task identity' \
  'handoff lacks contract correlation'
expect_grep skills/handing-off/SKILL.md 'SUPERSEDES_RESULT' 'handoff lacks result ordering'
expect_grep agents/verifier.md 'plan path, Task identity, contract version' \
  'verifier lacks acceptance correlation'
expect_grep agents/verifier.md 'reported mechanical deviation' 'verifier does not reproduce deviations'
expect_grep agents/reviewer.md 'reported mechanical deviation' 'reviewer does not examine deviations'
expect_grep agents/reviewer.md 'fixed Interfaces and invariants' 'reviewer lacks contract fence'

# T5 — operating documentation and seven-scenario validation
expect_grep README.md '### Adaptive execution handoff' 'README lacks adaptive handoff'
expect_grep README.md 'execution-contract: 1' 'README lacks active contract version'
VALIDATION='docs/superpowers/validation/2026-07-14-adaptive-execution-handoff-validation.md'
for scenario in 'Dependency policy conflict' 'Unreachable test seam' \
  'Protected-branch push' 'Audited execution stall' 'Workspace conflict' \
  'Healthy mechanical drift' 'Verifier-feedback repair'; do
  expect_grep "$VALIDATION" "## $scenario" "validation lacks $scenario"
done
expect_grep "$VALIDATION" '## Rollout scorecard' 'validation lacks measurable scorecard'
expect_grep "$VALIDATION" 'Coordinated rollback target' 'validation lacks rollback target'
expect_grep "$VALIDATION" 'HIGH or MEDIUM' 'validation lacks deviation quality check'

printf 'execution-handoff text tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
