#!/usr/bin/env bash
# tests/test_install_skills.sh — install the vendored skills into a sandbox HOME
# and verify resolution, install, manifest, --check OK, and drift detection.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

export AGENT_TEAM_SKIP_INSTALL_TEST=1

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT          # test-harness cleanup, authored via Write, run by the test
export HOME="$SANDBOX"
mkdir -p "$HOME/.claude/skills"

# Stub the plugin cache so superpowers:* refs in agent frontmatter and the
# architect's situational superpowers:brainstorming resolve. Enumerate every
# superpowers skill any agent frontmatter references.
PLUGVER="$HOME/.claude/plugins/cache/claude-plugins-official/superpowers/6.1.1/skills"
for sp in brainstorming test-driven-development verification-before-completion writing-plans \
          systematic-debugging requesting-code-review receiving-code-review subagent-driven-development \
          executing-plans using-git-worktrees; do
  mkdir -p "$PLUGVER/$sp"
  printf -- '---\nname: %s\ndescription: stub\n---\n' "$sp" > "$PLUGVER/$sp/SKILL.md"
done

# 1) install into an empty ~/.claude/skills succeeds
if bash "$REPO/install.sh" >/dev/null 2>&1; then ok; else bad "install.sh did not exit 0 against empty sandbox HOME"; fi

# 2) all ten skills present with an exact-name SKILL.md (uppercase-safe listing)
for name in coding-standards code-review secure-secrets write-ticket review-ticket \
            task-verification writing-business-requirements audit-requirements-document \
            plan-review ux-to-ui-design; do
  found="$(cd "$HOME/.claude/skills/$name" 2>/dev/null && ls | grep -Fx 'SKILL.md')"
  [ "$found" = "SKILL.md" ] && ok || bad "skill $name missing exact-name SKILL.md after install"
done
# every vendored file arrived at its mapped path
vendored_count="$(cd "$REPO/skills" && find . -type f | wc -l | tr -d ' ')"
if [ "$vendored_count" -eq 0 ]; then
  bad "no vendored skills files found under $REPO/skills — cannot verify mapped paths"
else
  ( cd "$REPO/skills" && find . -type f ) | while read -r rel; do
    rel="${rel#./}"
    [ -f "$HOME/.claude/skills/$rel" ] || echo "MISSINGFILE $rel"
  done | grep -q MISSINGFILE && bad "a vendored skills file did not arrive at its mapped path" || ok
fi

# 3) manifest has a skills/... entry with correct hash for every vendored file
MANIFEST="$HOME/.claude/agent-team-manifest.json"
miss=0
if [ "$vendored_count" -eq 0 ]; then
  bad "no vendored skills files found under $REPO/skills — cannot verify manifest hashes"
else
  ( cd "$REPO/skills" && find . -type f ) | while read -r rel; do
    rel="${rel#./}"; key="skills/$rel"
    want="$(shasum -a 256 "$REPO/skills/$rel" | awk '{print $1}')"
    got="$(jq -r --arg k "$key" '.files[$k] // empty' "$MANIFEST")"
    [ "$got" = "$want" ] || { echo "BADHASH $key"; }
  done | grep -q BADHASH && bad "manifest missing/incorrect hash for a skills file" || ok
fi

# 4) --check exits 0 and prints OK
out="$(bash "$REPO/install.sh" --check 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'check: OK'; } && ok || bad "--check did not report OK after clean install"

# 5a) append a byte to an installed skill file -> DRIFT, nonzero
printf 'x' >> "$HOME/.claude/skills/ux-to-ui-design/SKILL.md"
out="$(bash "$REPO/install.sh" --check 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'DRIFT'; } && ok || bad "--check did not detect DRIFT on edited skill file"

# 5b) remove that installed skill file -> MISSING, nonzero
rm -f "$HOME/.claude/skills/ux-to-ui-design/SKILL.md"   # test-sandbox mutation, run by the test
out="$(bash "$REPO/install.sh" --check 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'MISSING'; } && ok || bad "--check did not detect MISSING on removed skill file"

# 6) a repo skills dir with no SKILL.md fails validation before any copy.
#    Build a throwaway copy of the repo tree in the sandbox, add an empty skill dir.
BROKENREPO="$SANDBOX/brokenrepo"
cp -R "$REPO" "$BROKENREPO"
rm -rf "$BROKENREPO/.git"
mkdir -p "$BROKENREPO/skills/no-skill-md-here"
printf 'not a skill\n' > "$BROKENREPO/skills/no-skill-md-here/notes.md"
if bash "$BROKENREPO/install.sh" --check >/dev/null 2>&1; then
  bad "install validation passed a skills dir with no SKILL.md"
else ok; fi

echo "install-skills tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
