#!/usr/bin/env bash
# tests/test_bug_route_handoff.sh — pin the bug-to-fix evidence handoff across
# its touchpoints (debugger.md, orchestrator.md, builder.md, verifier.md, and
# the agent-workforce skill's two mirrored routing sentences) plus the
# rendered Codex profiles that carry the debugger and builder prose forward.
# Locates the repository from its own path so it can be run against a copied
# tree (see tests/test_bug_route_handoff_mutations.sh).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
DEBUGGER="$REPO/agents/debugger.md"
ORCHESTRATOR="$REPO/agents/orchestrator.md"
BUILDER="$REPO/agents/builder.md"
VERIFIER="$REPO/agents/verifier.md"
WORKFORCE_SKILL="$REPO/skills/agent-workforce/SKILL.md"
DEBUGGER_TOML="$REPO/codex/agents/agent_workforce_debugger.toml"
BUILDER_TOML="$REPO/codex/agents/agent_workforce_builder.toml"

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# Count occurrences of a literal string, never matching lines — a cosmetic
# reflow that joins or splits lines must not change this number.
count_occurrences() {
  grep -o -F -- "$2" "$1" 2>/dev/null | wc -l | tr -d ' '
}

# A prose phrase can legitimately wrap across a markdown source line — and a
# rewrapped continuation can pick up leading indent (a list item, a quoted
# block) — without any semantic change, so a literal multi-word match has to
# look at the text with all newlines, tabs, and repeated spaces folded down to
# single spaces rather than at raw source lines.
joined_contains() {
  tr '\n\t' '  ' < "$1" | tr -s ' ' | grep -qF -- "$2"
}

# Prints the whole blank-line-delimited paragraph containing $2, so a check
# that needs "does this paragraph also require Y" is scoped to the paragraph
# rather than to an arbitrary fixed number of following lines.
paragraph_containing() {
  python3 - "$1" "$2" <<'PY'
import sys
path, needle = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
paras = text.split("\n\n")
hits = [p for p in paras if needle in p]
sys.stdout.write(hits[0] if hits else "")
PY
}

for f in "$DEBUGGER" "$ORCHESTRATOR" "$BUILDER" "$VERIFIER" "$WORKFORCE_SKILL"; do
  [ -f "$f" ] || bad "missing role document: $f"
done

# --- 1. agents/debugger.md: the reproduction command is its own labeled
# report line, including the explicit "none" form — and the "none" form
# costs more than a thin excuse: it names what was tried, what would unblock
# a reproduction, and downgrades the report to partial. ---
repro_count="$(count_occurrences "$DEBUGGER" 'REPRO COMMAND:')"
[ "${repro_count:-0}" -ge 2 ] 2>/dev/null && ok \
  || bad "agents/debugger.md: expected >=2 occurrences of 'REPRO COMMAND:' (report line + none-form), found ${repro_count:-0}"
grep -q 'REPRO COMMAND: none' "$DEBUGGER" && ok \
  || bad "agents/debugger.md: missing the explicit 'REPRO COMMAND: none' form"
# Scoped to the whole blank-line-delimited paragraph containing the 'none'
# form, not a fixed line count — a rewrap that pushes any of the three
# requirements below onto a later line must not escape this check.
none_context="$(paragraph_containing "$DEBUGGER" 'REPRO COMMAND: none' | tr '\n' ' ')"
case "$none_context" in
  *'what you tried'*|*'what was tried'*) ok ;;
  *) bad "agents/debugger.md: the 'none' form does not require stating what was tried" ;;
esac
case "$none_context" in
  *'access or artifact'*) ok ;;
  *) bad "agents/debugger.md: the 'none' form does not require naming what access or artifact would unblock a reproduction" ;;
esac
case "$none_context" in
  *'partial'*) ok ;;
  *) bad "agents/debugger.md: the 'none' form does not require reporting partial rather than complete" ;;
esac
redcapable_context="$(grep -n -A1 'red-capable' "$DEBUGGER" | head -2)"
case "$redcapable_context" in
  *'goes red'*) ok ;;
  *) bad "agents/debugger.md: 'red-capable' is used without a plain-words gloss at its first use" ;;
esac

# --- 2. agents/orchestrator.md: the symptom row carries the debugger's
# REPRO COMMAND forward as AC-1's Check, quoted exactly, into the builder,
# executor, and verifier dispatches — the "carried verbatim" wording is
# gone, since it contradicts the dispatch guard's tagged-criterion shape —
# and the existing instruction to relay the actionable first sentence
# survives. The dispatch-mechanics paragraph names the same REPRO COMMAND
# line as a third source of the acceptance bar, alongside the architect's
# plan and the human's request. ---
symptom_row="$(grep -n '^| Symptom (' "$ORCHESTRATOR")"
if [ -n "$symptom_row" ]; then
  case "$symptom_row" in
    *'quoted exactly'*'builder dispatch'*'executor dispatch'*'verifier dispatch'*) ok ;;
    *) bad "agents/orchestrator.md: symptom row does not carry AC-1's Check, quoted exactly, into the builder, executor, and verifier dispatches: $symptom_row" ;;
  esac
  case "$symptom_row" in
    *'none'*) ok ;;
    *) bad "agents/orchestrator.md: symptom row does not name the 'none' case the orchestrator must author itself" ;;
  esac
  case "$symptom_row" in
    *'carried verbatim'*) bad "agents/orchestrator.md: symptom row still says 'carried verbatim', which the dispatch guard's tagged-criterion shape contradicts" ;;
    *) ok ;;
  esac
else
  bad "agents/orchestrator.md: no symptom row found (expected a line starting '| Symptom (')"
fi
actionable_count="$(count_occurrences "$ORCHESTRATOR" 'actionable first sentence')"
[ "${actionable_count:-0}" -ge 1 ] 2>/dev/null && ok \
  || bad "agents/orchestrator.md: 'actionable first sentence' instruction did not survive the edit"
joined_contains "$ORCHESTRATOR" "from the debugger's \`REPRO COMMAND:\` line when the route is a symptom repair" && ok \
  || bad "agents/orchestrator.md: dispatch-mechanics paragraph does not name the debugger's REPRO COMMAND line as a source of the acceptance bar"

# --- 3. agents/builder.md: the repair stance names its trigger, references
# the REPRO COMMAND line, forbids adjacent cleanup or refactor, and cites the
# preloaded debugging discipline as the governing loop — and separately, a
# reproduction command's target assertion is protected the same way the
# acceptance-suite files are: new tests may be added, the existing assertion
# may not be weakened. ---
grep -q "repair routed from a debugger's diagnosis" "$BUILDER" && ok \
  || bad "agents/builder.md: repair stance does not name its trigger"
grep -q 'REPRO COMMAND:' "$BUILDER" && ok \
  || bad "agents/builder.md: repair stance does not reference the debugger's REPRO COMMAND: line"
grep -q 'no adjacent cleanup' "$BUILDER" && ok \
  || bad "agents/builder.md: repair stance does not forbid adjacent cleanup"
grep -q 'no refactor' "$BUILDER" && ok \
  || bad "agents/builder.md: repair stance does not forbid refactor beyond the defect"
grep -q 'governing loop' "$BUILDER" && ok \
  || bad "agents/builder.md: repair stance does not cite the debugging discipline as the governing loop"
grep -q 'reproduction command' "$BUILDER" && ok \
  || bad "agents/builder.md: missing the reproduction-command assertion-protection clause"
# Scoped to the new clause's own closing half, not the pre-existing
# acceptance-suite sentence a few lines above that happens to end the same
# way — deleting only this clause's closing half must not still pass by
# accident.
joined_contains "$BUILDER" "a reproduction command you believe is wrong is a diagnosis defect to report, never a file to edit" && ok \
  || bad "agents/builder.md: does not say a wrong reproduction command is a diagnosis defect to report, never a file to edit"

# --- 4. agents/verifier.md: when a criterion's Check is a reproduction
# command carried from a diagnosis, the verifier inspects the diff for a
# weakened assertion inside that command's target and reports any as a
# blocking finding above the pass/fail table. ---
grep -q 'reproduction command' "$VERIFIER" && ok \
  || bad "agents/verifier.md: missing the reproduction-command diff-inspection clause"
grep -q 'blocking finding' "$VERIFIER" && ok \
  || bad "agents/verifier.md: reproduction-command clause does not report a modified target as a blocking finding"

# --- 5. skills/agent-workforce/SKILL.md: both mirrored sentences (symptom
# routing, and the criteria-authoring source list) name the debugger's
# REPRO COMMAND line — a session driven by the skill rather than the
# orchestrator role document must reach the same rule. ---
skill_repro_count="$(count_occurrences "$WORKFORCE_SKILL" 'REPRO COMMAND')"
[ "${skill_repro_count:-0}" -ge 2 ] 2>/dev/null && ok \
  || bad "skills/agent-workforce/SKILL.md: expected >=2 occurrences of 'REPRO COMMAND' (symptom-routing rule + criteria-authoring sentence), found ${skill_repro_count:-0}"
# Scoped to the routing rule's own line, not two independent file-wide
# greps — confirming both substrings exist somewhere in the file proves
# nothing about whether the routing sentence itself names REPRO COMMAND.
routing_line="$(grep -F 'Route symptom-shaped requests' "$WORKFORCE_SKILL")"
if [ -n "$routing_line" ]; then
  case "$routing_line" in
    *'REPRO COMMAND'*) ok ;;
    *) bad "skills/agent-workforce/SKILL.md: symptom-routing rule does not name the debugger's REPRO COMMAND line" ;;
  esac
else
  bad "skills/agent-workforce/SKILL.md: no symptom-routing rule found (expected a line starting 'Route symptom-shaped requests')"
fi
joined_contains "$WORKFORCE_SKILL" "from the debugger's \`REPRO COMMAND:\` line when the route is a symptom repair" && ok \
  || bad "skills/agent-workforce/SKILL.md: criteria-authoring sentence does not name the debugger's REPRO COMMAND line as a source"

# --- 6. No restatement of the debugging skill's Phase 5 seam mechanics in a
# role document. Measured by actual duplicated phrasing lifted verbatim from
# that phase, not the "Phase N" label, which a legitimate future mention
# could use without restating anything (in the manner of the VOCAB list in
# tests/test_plan_formatting_drift.sh). ---
PHASE5_VOCAB=(
  'at a seam where the test exercises the real bug pattern as it occurred'
  'the missing seam is itself a finding; record it'
  're-run the Phase 1 loop against the original, un-minimised scenario'
)
for f in "$DEBUGGER" "$ORCHESTRATOR" "$BUILDER"; do
  found=0
  for v in "${PHASE5_VOCAB[@]}"; do
    # joined_contains, not grep -qF: two of these three phrases exist in
    # skills/debugging/SKILL.md only as line-wrapped text, so a raw-line
    # match can never fire on the wrapped form actually written there.
    if joined_contains "$f" "$v"; then
      bad "$f restates skills/debugging/SKILL.md Phase 5 verbatim: \"$v\""
      found=1
    fi
  done
  [ "$found" -eq 0 ] && ok
done

# --- 7. The rendered Codex profiles carry the same pinned prose forward, so
# the Claude and Codex surfaces cannot silently diverge. ---
if [ -f "$DEBUGGER_TOML" ]; then
  toml_repro_count="$(count_occurrences "$DEBUGGER_TOML" 'REPRO COMMAND:')"
  [ "${toml_repro_count:-0}" -ge 2 ] 2>/dev/null && ok \
    || bad "rendered Codex debugger profile lost the REPRO COMMAND: report line"
  grep -q 'REPRO COMMAND: none' "$DEBUGGER_TOML" && ok \
    || bad "rendered Codex debugger profile lost the REPRO COMMAND: none form"
else
  bad "rendered Codex debugger profile not found at $DEBUGGER_TOML"
fi

if [ -f "$BUILDER_TOML" ]; then
  grep -q 'REPRO COMMAND:' "$BUILDER_TOML" && ok \
    || bad "rendered Codex builder profile lost the repair stance's REPRO COMMAND reference"
  grep -q 'no adjacent cleanup' "$BUILDER_TOML" && ok \
    || bad "rendered Codex builder profile lost the repair stance's cleanup prohibition"
else
  bad "rendered Codex builder profile not found at $BUILDER_TOML"
fi

# --- 8. A reproduction command built as a throwaway outside every checkout
# can outlive the workspace it ran in. agents/debugger.md prefers a command
# runnable from the checkout and, when the loop was a throwaway anyway, says
# so plainly on the REPRO COMMAND: line; agents/orchestrator.md, on receiving
# such a flag, authors AC-1's Check as a durable equivalent and says it did
# so, rather than carrying forward a command that may already be gone. ---
grep -q 'throwaway' "$DEBUGGER" && ok \
  || bad "agents/debugger.md: does not address a throwaway reproduction command"
joined_contains "$DEBUGGER" "since the builder and the verifier may need to run it again long after your own workspace is gone" && ok \
  || bad "agents/debugger.md: does not say why a throwaway repro must be flagged on the REPRO COMMAND: line"
grep -q 'throwaway' "$ORCHESTRATOR" && ok \
  || bad "agents/orchestrator.md: does not address a throwaway reproduction command"
joined_contains "$ORCHESTRATOR" "author AC-1's Check as a durable equivalent" && ok \
  || bad "agents/orchestrator.md: does not author a durable Check in place of a flagged throwaway repro"

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
