#!/usr/bin/env bash
# tests/test_plan_formatting_drift.sh — enforce single-source plan-formatting
# framing rules (skills/agent-workforce/references/plan-formatting.md) across
# every consumer surface: orchestrator, builder, and the rendered Codex profile.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
REF="$REPO/skills/agent-workforce/references/plan-formatting.md"
ORCH="$REPO/agents/orchestrator.md"
BUILDER="$REPO/agents/builder.md"
BUILDER_TOML="$REPO/codex/agents/agent_workforce_builder.toml"

PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

# The framing-rule vocabulary: distinctive strings that only belong in the
# single-source reference file's rule body, never restated in a consumer.
# Each is a fragment of an actual framing RULE (the notation table, the XML
# tag list, the tier->stance mechanics) — not the fixed labels themselves,
# which consumers legitimately cite as outcome markers (e.g. orchestrator.md
# citing `unframed-fallback` as the fallback it applied).
VOCAB=(
  '<plan_reference>'
  '<in_scope_slice>'
  '<terminal_result>'
  'Markdown headers of the SAME fields'
  'de-emphasize prescriptive step ordering'
)

check_no_restatement() {
  local file="$1" label="$2" found=0
  for v in "${VOCAB[@]}"; do
    if grep -qF -- "$v" "$file"; then
      bad "$label restates framing-rule vocabulary: \"$v\""
      found=1
    fi
  done
  [ "$found" -eq 0 ] && ok
}

# (a) Vocabulary lives only in the reference file.
for v in "${VOCAB[@]}"; do
  grep -qF -- "$v" "$REF" && ok || bad "reference file missing expected vocabulary: \"$v\""
done
check_no_restatement "$ORCH" "agents/orchestrator.md"
check_no_restatement "$BUILDER" "agents/builder.md"

# (b) Orchestrator cites the single source.
grep -qF 'skills/agent-workforce/references/plan-formatting.md' "$ORCH" && ok || bad "agents/orchestrator.md does not cite plan-formatting.md"

# (c) Builder cites the single source, and the citation survives Codex rendering.
grep -qF 'skills/agent-workforce/references/plan-formatting.md' "$BUILDER" && ok || bad "agents/builder.md does not cite plan-formatting.md"
if [ -f "$BUILDER_TOML" ]; then
  grep -qF 'skills/agent-workforce/references/plan-formatting.md' "$BUILDER_TOML" && ok || bad "rendered Codex builder profile lost the plan-formatting.md citation"
else
  bad "rendered Codex builder profile not found at $BUILDER_TOML"
fi

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
