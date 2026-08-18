#!/usr/bin/env bash
# tests/test_dispatch_guard.sh — verifies the PreToolUse(Agent) dispatch guard: the
# specialist allowlist, the criteria-before-code floor, and the change declaration that
# claims a workspace in the work register and builds it.
#
# Output contract: `PASS [<label>]` / `FAIL [<label>]: <why>` per case, then a trailing
# `passed=<n> failed=<n>`. The world every case runs in — its own git project, its own
# register, its own telemetry — is tests/lib/dispatch-guard-fixture.sh. Two groups of
# cases live in their own files and are sourced here, so the whole suite is still one
# command: tests/lib/dispatch-guard-change-cases.sh (claim, create, adopt, resume, the
# writer slot) and tests/lib/dispatch-guard-lane-cases.sh (lane routing and the human
# override).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/dispatch-guard-fixture.sh
. "$HERE/lib/dispatch-guard-fixture.sh"

# --- the roster -------------------------------------------------------------
# Roles that declare no change and are policed for none pass with a bare payload.
for a in architect debugger reviewer researcher ops scribe ticketer; do
  expect_allow "$(agent_json "$a")" "valid: $a allows"
  expect_allow "$(agent_json "agent-workforce:$a")" "valid plugin namespace: $a allows"
done

# Missing / empty / harness-default / unknown all block.
expect_block "$(jq -cn '{tool_name:"Agent",tool_input:{description:"do a thing"}}')" "missing subagent_type blocks"
expect_block "$(agent_json '')" "empty subagent_type blocks"
expect_block "$(agent_json 'general-purpose')" "general-purpose blocks"
expect_block "$(agent_json 'designer')" "unknown type blocks"
expect_block "$(agent_json 'other-plugin:builder')" "foreign plugin namespace blocks"
# Substring of a valid name must NOT match (space-delimited membership).
expect_block "$(agent_json 'archi')" "substring 'archi' blocks"
expect_block "$(agent_json 'build')" "substring 'build' blocks"
# A non-Agent tool passes through untouched.
expect_allow "$(jq -cn '{tool_name:"Bash",tool_input:{command:"ls"}}')" "non-Agent tool passes"
expect_allow "$(jq -cn '{tool_name:"Read",tool_input:{file_path:"/tmp/x"}}')" "valid JSON, non-Agent tool_name passes"
# Malformed / non-JSON / empty stdin must BLOCK (fail closed), never be coerced to an
# empty tool_name and allowed.
expect_block "not json at all" "malformed stdin blocks"
expect_block "" "empty stdin blocks"
expect_block "{" "truncated JSON blocks"
# A compound value spanning two valid tokens must not bypass by containment.
expect_block "$(agent_json 'architect builder')" "compound 'architect builder' blocks"
expect_block "$(agent_json ' architect ')" "padded exact-looking value blocks"

# --- criteria before code ---------------------------------------------------
# A builder, verifier, or test-author dispatch must carry an ACCEPTANCE CRITERIA block
# authored upstream of the code, and the block must survive the same falsifiability lint
# plans are held to (tools/lint_acceptance_checks.py): at least one tagged criterion, no
# BLOCK findings. A string match alone is a checkbox; the lint is the floor.
dg_fixture criteria || { printf 'FAIL [criteria fixture]: could not build the project\n'; exit 1; }
CRIT_PROJ="$PROJ"
crit_payload() { # $1 role $2 prompt
  dg_payload "$1" "$2" sess-criteria "$CRIT_PROJ" ""
}

expect_block "$(agent_json builder)" "builder without prompt blocks (no criteria)"
expect_block "$(agent_json_p builder 'implement the widget, TDD')" "builder prompt without criteria blocks"
expect_block "$(agent_json verifier)" "verifier without prompt blocks (no criteria)"
expect_block "$(agent_json_p verifier 'run the suite')" "verifier prompt without criteria blocks"
expect_allow "$(crit_payload builder "$(change_prompt criteria-check)")" \
  "builder with lint-clean tagged criteria allows"
expect_allow "$(agent_json_p verifier "$CRITERIA_BODY")" "verifier with lint-clean tagged criteria allows"
expect_allow "$(crit_payload 'agent-workforce:builder' "$(change_prompt criteria-check)")" \
  "plugin-namespace builder with criteria allows"
expect_block "$(agent_json_p 'agent-workforce:builder' 'do it')" "plugin-namespace builder without criteria blocks"
expect_block "$(agent_json_p test-author 'write the acceptance tests')" "test-author without criteria blocks"
# Its own change, because the builder cases above hold criteria-check's writer slot and
# one change admits one writer at a time — which is the mechanism working, not a clash.
expect_allow "$(crit_payload test-author "$(change_prompt criteria-author)")" \
  "test-author with lint-clean criteria allows"

# Quality floor: the marker alone is no longer enough.
expect_block "$(agent_json_p builder 'Build it.
ACCEPTANCE CRITERIA: do the task well')" "vacuous criteria line blocks (no tagged criterion)"
expect_block "$(agent_json_p builder 'Build it.
ACCEPTANCE CRITERIA
- [ ] AC-1 (mechanical): it works. Check: `echo ok` -> expects ok.')" "tautological check blocks"
expect_block "$(agent_json_p builder 'Build it.
ACCEPTANCE CRITERIA
- [ ] AC-1 (mechanical): file present. Check: `test -f slug.py` -> expects exit 0.')" "silent existence probe blocks"
expect_allow "$(crit_payload builder 'Build it.
CHANGE: criteria-check
ACCEPTANCE CRITERIA
- [ ] AC-1 (mechanical): file present. Check: `test -f slug.py || echo "why: slug.py missing"` -> expects exit 0.')" \
  "same probe with failure output allows"

# --- the declaration a git-mutating dispatch must carry ---------------------
# The unit of isolation is the CHANGE: a dispatch names it, and the guard claims it and
# builds its worktree. The retired markers are refused rather than ignored, because a
# line the runtime no longer reads is worse than no line at all — the 2026-08-04
# incident was a declaration that looked enforced and was not.
expect_block "$(crit_payload builder "Implement it.
WORKTREE: $CRIT_PROJ/.claude/worktrees/task-a-b1
$CRITERIA_BODY")" \
  "a WORKTREE: line is refused and names CHANGE:"
expect_block "$(dg_payload executor "PARALLEL_SAFE: no git mutation in this dispatch
Run the finalizer" sess-criteria "$CRIT_PROJ" "")" \
  "the retired PARALLEL_SAFE literal is refused and names the new one"
# Detection is the MARKER's presence at the start of a line, never a non-empty path after
# it: a bare marker was silently ignored, which is the one outcome this rule exists to
# forbid — "refused, never ignored". The declaration beside it is legal, so nothing else in
# the guard could account for a refusal.
expect_block "$(dg_payload builder "Implement it.
WORKTREE:
CHANGE: bare-marker
$CRITERIA_BODY" sess-criteria "$CRIT_PROJ" "")" \
  "a bare WORKTREE: line with no path is refused"
expect_block "$(agent_json_p builder "Implement it.
$CRITERIA_BODY")" \
  "a builder with neither CHANGE: nor PARALLEL_SAFE is refused"
expect_block "$(agent_json_p executor 'Run the finalizer')" \
  "an executor with neither CHANGE: nor PARALLEL_SAFE is refused"
expect_allow "$(agent_json_p executor 'PARALLEL_SAFE: this dispatch writes nothing
Report what the suite says')" \
  "valid: executor allows when it declares it writes nothing"
expect_allow "$(agent_json_p deployer 'PARALLEL_SAFE: this dispatch writes nothing
Read the deploy log')" \
  "valid: deployer allows when it declares it writes nothing"

# The refusal must name the replacement, not just say no.
run "$(crit_payload builder "Implement it.
WORKTREE: $CRIT_PROJ/.claude/worktrees/task-a-b1
$CRITERIA_BODY")"
case "$OUT" in
  *"CHANGE: <slug>"*) pass_case "the WORKTREE: refusal names the CHANGE: line that replaces it" ;;
  *) fail_case "the WORKTREE: refusal names the CHANGE: line that replaces it" "observed: $OUT" ;;
esac
run "$(dg_payload executor "PARALLEL_SAFE: no git mutation in this dispatch
Run it" sess-criteria "$CRIT_PROJ" "")"
case "$OUT" in
  *"PARALLEL_SAFE: this dispatch writes nothing"*)
    pass_case "the retired PARALLEL_SAFE refusal names the literal that replaces it" ;;
  *) fail_case "the retired PARALLEL_SAFE refusal names the literal that replaces it" "observed: $OUT" ;;
esac

# --- claiming, creating, adopting, resuming ---------------------------------
# A declared change is claimed in the register and its worktree is built as a side
# effect of the dispatch. Those cases carry their own fixtures and live in their own
# file; sourcing it runs them.
# shellcheck source=tests/lib/dispatch-guard-change-cases.sh
. "$HERE/lib/dispatch-guard-change-cases.sh"

# --- the dispatch-count budget ratchet --------------------------------------
# Default checkpoint 10 (hooks/agent-team-budgets.json). The transcript holds N PRIOR
# dispatches and the guard evaluates the (N+1)th attempt.
write_resolved_dispatches_transcript() { # $1 count -> prints path
  local path i=0
  path="$(mktemp "$WORK/budget.XXXXXX")"
  : > "$path"
  while [ "$i" -lt "$1" ]; do
    jq -cn --arg id "toolu_budget_$i" \
      '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Agent",input:{subagent_type:"scribe"}}]}}' \
      >> "$path"
    jq -cn --arg id "toolu_budget_$i" \
      '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:[{type:"text",text:"done"}]}]}}' \
      >> "$path"
    i=$((i + 1))
  done
  printf '%s' "$path"
}

NINE_PRIOR="$(write_resolved_dispatches_transcript 9)"
expect_block "$(agent_json_with_transcript scribe "$NINE_PRIOR" "write the status note")" \
  "10th dispatch attempt without ack blocks at checkpoint 10"
expect_allow \
  "$(agent_json_with_transcript scribe "$NINE_PRIOR" "WORKFORCE_BUDGET_ACK: 10 dispatches — continuing because standard-tier route mid-build")" \
  "10th dispatch attempt with WORKFORCE_BUDGET_ACK allows"
TEN_PRIOR="$(write_resolved_dispatches_transcript 10)"
expect_allow "$(agent_json_with_transcript scribe "$TEN_PRIOR" "write the status note")" \
  "11th dispatch attempt (past the 10th) without ack allows"
EIGHTEEN_PRIOR="$(write_resolved_dispatches_transcript 18)"
expect_allow "$(agent_json_with_transcript scribe "$EIGHTEEN_PRIOR" "write the status note")" \
  "19th dispatch attempt without ack allows (next checkpoint is 20)"

# --- the writing turn -------------------------------------------------------
# When a change's writer slot is released, kept, or never taken, and what a dispatch the
# checkpoint above refuses leaves behind. Sourced after both the change cases (whose
# prior_dispatch_transcript these reuse) and the ratchet section above (whose
# write_resolved_dispatches_transcript the checkpoint case reuses).
# shellcheck source=tests/lib/dispatch-guard-writer-cases.sh
. "$HERE/lib/dispatch-guard-writer-cases.sh"

# --- lane routing -----------------------------------------------------------
# shellcheck source=tests/lib/dispatch-guard-lane-cases.sh
. "$HERE/lib/dispatch-guard-lane-cases.sh"

# --- roster drift -----------------------------------------------------------
# The guard allowlist, agents/, and the orchestrator's Agent(...) tools must name
# exactly the same specialists, or a grown agent silently becomes undispatchable.
GUARD_ROSTER="$(grep '^readonly VALID_SPECIALISTS=' "$GUARD" | sed 's/.*"\(.*\)".*/\1/' | tr ' ' '\n' | sort)"
AGENT_ROSTER="$(cd "$HERE/../agents" && ls *.md | sed 's/\.md$//' | grep -v '^orchestrator$' | sort)"
ORCH_ROSTER="$(grep -o 'Agent([a-z-]*)' "$HERE/../agents/orchestrator.md" | sed 's/Agent(\(.*\))/\1/' | sort -u)"
if [ "$GUARD_ROSTER" = "$AGENT_ROSTER" ]; then
  pass_case "the guard allowlist matches agents/*.md"
else
  fail_case "the guard allowlist matches agents/*.md" "guard VALID_SPECIALISTS != agents/*.md"
fi
if [ "$ORCH_ROSTER" = "$AGENT_ROSTER" ]; then
  pass_case "the orchestrator's Agent(...) tools match agents/*.md"
else
  fail_case "the orchestrator's Agent(...) tools match agents/*.md" "orchestrator Agent(...) != agents/*.md"
fi

report_totals
