#!/usr/bin/env bash
# tests/test_chatgpt_plugin.sh — validate the ChatGPT/Codex plugin package.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
MANIFEST="$REPO/.codex-plugin/plugin.json"
MARKETPLACE="$REPO/.claude-plugin/marketplace.json"
WORKFORCE_SKILL="$REPO/skills/agent-workforce/SKILL.md"
OPENAI_YAML="$REPO/skills/agent-workforce/agents/openai.yaml"
MODEL_POLICY="$REPO/codex/model-policy.json"
CODEX_INSTALLER="$REPO/install-codex.sh"

PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

for file in "$MANIFEST" "$MARKETPLACE"; do
  jq empty "$file" >/dev/null 2>&1 && ok || bad "${file#$REPO/} is not valid JSON"
done

[ "$(jq -r '.name' "$MANIFEST")" = "agent-workforce" ] \
  && ok || bad "Codex manifest name is not agent-workforce"
[ "$(jq -r '.version' "$MANIFEST")" = "1.0.0" ] \
  && ok || bad "Codex manifest version does not match the release"
[ "$(jq -r '.skills' "$MANIFEST")" = "./skills/" ] \
  && ok || bad "Codex manifest does not expose the bundled skills"

if jq -e '
  (.interface.displayName | length > 0)
  and (.interface.shortDescription | length > 0)
  and (.interface.longDescription | length > 0)
  and (.interface.developerName | length > 0)
  and (.interface.category | length > 0)
  and (.interface.capabilities | type == "array" and length > 0)
  and (.interface.defaultPrompt | type == "array" and length > 0 and length <= 3)
' "$MANIFEST" >/dev/null; then
  ok
else
  bad "Codex manifest is missing required install-surface metadata"
fi

if jq -e '
  .name == "agent-workforce"
  and (.owner.name | length > 0)
  and .plugins[0].name == "agent-workforce"
  and .plugins[0].source.source == "url"
  and .plugins[0].source.url == "https://github.com/jayheavner/agent-workforce.git"
  and .plugins[0].policy.installation == "AVAILABLE"
  and .plugins[0].policy.authentication == "ON_INSTALL"
  and (.plugins[0].category | length > 0)
' "$MARKETPLACE" >/dev/null; then
  ok
else
  bad "marketplace entry does not expose the repo-root plugin"
fi

[ -f "$WORKFORCE_SKILL" ] && ok || bad "portable agent-workforce skill is missing"
[ -f "$OPENAI_YAML" ] && ok || bad "agent-workforce OpenAI UI metadata is missing"
[ -f "$MODEL_POLICY" ] && ok || bad "Codex model policy is missing"
[ -f "$CODEX_INSTALLER" ] && ok || bad "Codex profile installer is missing"

if grep -q '^name: agent-workforce$' "$WORKFORCE_SKILL" \
   && grep -q '^description: .*\$agent-workforce' "$WORKFORCE_SKILL" \
   && ! grep -q '\[TODO:' "$WORKFORCE_SKILL"; then
  ok
else
  bad "agent-workforce skill metadata is incomplete"
fi

grep -qF 'default_prompt: "Use $agent-workforce' "$OPENAI_YAML" \
  && ok || bad "OpenAI skill prompt does not explicitly invoke \$agent-workforce"

if grep -qF 'references/model-policy.md' "$WORKFORCE_SKILL" \
   && grep -qF 'do not silently fall back' "$WORKFORCE_SKILL" \
   && grep -qF 'agent_workforce_architect' "$WORKFORCE_SKILL" \
   && grep -qF 'agent_workforce_debugger' "$WORKFORCE_SKILL" \
   && grep -qF 'symptom-shaped' "$WORKFORCE_SKILL"; then
  ok
else
  bad "agent-workforce skill does not require the pinned Codex profile route"
fi

missing_link=0
while IFS= read -r link; do
  [ -n "$link" ] || continue
  [ -f "$REPO/skills/agent-workforce/$link" ] || {
    printf 'FAIL: agent-workforce skill has dangling link %s\n' "$link"
    missing_link=1
  }
done <<EOF
$(grep -oE '\]\([^)#][^)]*\)' "$WORKFORCE_SKILL" | sed 's/^](//; s/)$//' || true)
EOF
[ "$missing_link" -eq 0 ] && ok || FAIL=$((FAIL+1))

printf 'chatgpt-plugin tests: PASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
