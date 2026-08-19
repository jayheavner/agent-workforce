#!/usr/bin/env bash
# tests/test_bug_route_handoff.sh — pin the bug-to-fix evidence handoff across
# its three touchpoints (debugger.md, orchestrator.md, builder.md) and the
# rendered Codex profiles that carry the debugger and builder prose forward.
# Locates the repository from its own path so it can be run against a copied
# tree (see tests/test_bug_route_handoff_mutations.sh).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
DEBUGGER="$REPO/agents/debugger.md"
ORCHESTRATOR="$REPO/agents/orchestrator.md"
BUILDER="$REPO/agents/builder.md"
DEBUGGER_TOML="$REPO/codex/agents/agent_workforce_debugger.toml"
BUILDER_TOML="$REPO/codex/agents/agent_workforce_builder.toml"

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

for f in "$DEBUGGER" "$ORCHESTRATOR" "$BUILDER"; do
  [ -f "$f" ] || bad "missing role document: $f"
done

# --- 1. agents/debugger.md: the reproduction command is its own labeled
# report line, including the explicit "none" form for when no red-capable
# loop could be built. ---
repro_count="$(grep -c 'REPRO COMMAND:' "$DEBUGGER" 2>/dev/null || true)"
[ "${repro_count:-0}" -ge 2 ] 2>/dev/null && ok \
  || bad "agents/debugger.md: expected >=2 lines with 'REPRO COMMAND:' (report line + none-form), found ${repro_count:-0}"
grep -q 'REPRO COMMAND: none' "$DEBUGGER" && ok \
  || bad "agents/debugger.md: missing the explicit 'REPRO COMMAND: none' form"

# --- 2. agents/orchestrator.md: the symptom row carries the debugger's
# REPRO COMMAND forward as the repair's mechanical acceptance criterion, into
# both the builder dispatch and the verifier dispatch — and the existing
# instruction to relay the actionable first sentence survives. ---
symptom_row="$(grep -n '^| Symptom (' "$ORCHESTRATOR")"
if [ -n "$symptom_row" ]; then
  case "$symptom_row" in
    *'REPRO COMMAND'*'builder dispatch'*'verifier dispatch'*) ok ;;
    *) bad "agents/orchestrator.md: symptom row does not carry REPRO COMMAND into both the builder dispatch and the verifier dispatch: $symptom_row" ;;
  esac
  case "$symptom_row" in
    *'none'*) ok ;;
    *) bad "agents/orchestrator.md: symptom row does not name the 'none' case the orchestrator must author itself" ;;
  esac
else
  bad "agents/orchestrator.md: no symptom row found (expected a line starting '| Symptom (')"
fi
actionable_count="$(grep -c 'actionable first sentence' "$ORCHESTRATOR" 2>/dev/null || true)"
[ "${actionable_count:-0}" -ge 1 ] 2>/dev/null && ok \
  || bad "agents/orchestrator.md: 'actionable first sentence' instruction did not survive the edit"

# --- 3. agents/builder.md: a repair stance requires the regression test
# before the fix and forbids adjacent cleanup or refactor beyond the defect. ---
grep -q 'regression test' "$BUILDER" && ok \
  || bad "agents/builder.md: missing 'regression test' in a repair stance"
grep -q 'no adjacent cleanup' "$BUILDER" && ok \
  || bad "agents/builder.md: repair stance does not forbid adjacent cleanup"
grep -q 'no refactor' "$BUILDER" && ok \
  || bad "agents/builder.md: repair stance does not forbid refactor beyond the defect"
grep -q 're-run the' "$BUILDER" && grep -q 'un-minimised reproduction' "$BUILDER" && ok \
  || bad "agents/builder.md: repair stance does not require re-running the original un-minimised reproduction"

# --- 4. No restatement of the debugging skill's phase list in a role
# document — reference the discipline, never restate it. ---
for f in "$DEBUGGER" "$ORCHESTRATOR" "$BUILDER"; do
  if grep -qE 'Phase [0-9]' "$f"; then
    bad "$f restates the debugging skill's numbered phase list instead of citing it"
  else
    ok
  fi
done

# --- 5. The rendered Codex profiles carry the same pinned prose forward, so
# the Claude and Codex surfaces cannot silently diverge. ---
if [ -f "$DEBUGGER_TOML" ]; then
  toml_repro_count="$(grep -c 'REPRO COMMAND:' "$DEBUGGER_TOML" 2>/dev/null || true)"
  [ "${toml_repro_count:-0}" -ge 2 ] 2>/dev/null && ok \
    || bad "rendered Codex debugger profile lost the REPRO COMMAND: report line"
  grep -q 'REPRO COMMAND: none' "$DEBUGGER_TOML" && ok \
    || bad "rendered Codex debugger profile lost the REPRO COMMAND: none form"
else
  bad "rendered Codex debugger profile not found at $DEBUGGER_TOML"
fi

if [ -f "$BUILDER_TOML" ]; then
  grep -q 'regression test' "$BUILDER_TOML" && ok \
    || bad "rendered Codex builder profile lost the repair stance's regression test requirement"
  grep -q 'no adjacent cleanup' "$BUILDER_TOML" && ok \
    || bad "rendered Codex builder profile lost the repair stance's cleanup prohibition"
else
  bad "rendered Codex builder profile not found at $BUILDER_TOML"
fi

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
