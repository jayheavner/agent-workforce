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

# 1) install into an empty ~/.claude/skills succeeds
if bash "$REPO/install.sh" >/dev/null 2>&1; then ok; else bad "install.sh did not exit 0 against empty sandbox HOME"; fi

# 2) every pinned framework skill is present with an exact-name SKILL.md.
for name in auditing-requirements close-ticket convene-panel debugging finishing-a-branch \
            handing-off handling-secrets interviewing op-migration planning project-policy \
            review-ticket reviewing tdd ux-to-ui-design verifying write-ticket \
            writing-business-requirements writing-skills; do
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

# 7) requires: dependencies fail closed when their target is unavailable.
BROKENREQ="$SANDBOX/broken-requires"
cp -R "$REPO" "$BROKENREQ"
rm -rf "$BROKENREQ/.git"
mkdir -p "$BROKENREQ/skills/broken-requires"
printf '%s\n' '---' 'name: broken-requires' 'description: dependency failure fixture' \
  'requires: [not-installed-anywhere]' '---' '# Broken Requires' \
  > "$BROKENREQ/skills/broken-requires/SKILL.md"
if bash "$BROKENREQ/install.sh" --check >/dev/null 2>&1; then
  bad "install validation passed an unresolved requires: dependency"
else ok; fi

# 8) unregistered policy:<key> tokens fail closed.
BROKENPOLICY="$SANDBOX/broken-policy"
cp -R "$REPO" "$BROKENPOLICY"
rm -rf "$BROKENPOLICY/.git"
mkdir -p "$BROKENPOLICY/skills/broken-policy"
printf '%s\n' '---' 'name: broken-policy' 'description: policy registry failure fixture' \
  '---' '# Broken Policy' 'Resolve policy:not-registered.' \
  > "$BROKENPOLICY/skills/broken-policy/SKILL.md"
if bash "$BROKENPOLICY/install.sh" --check >/dev/null 2>&1; then
  bad "install validation passed an unregistered policy key"
else ok; fi

# 9) the shipped project-policy must cover every active registered key.
MISSINGPOLICY="$SANDBOX/missing-policy-value"
cp -R "$REPO" "$MISSINGPOLICY"
rm -rf "$MISSINGPOLICY/.git"
sed '/^\*\*coverage\*\*/d' "$MISSINGPOLICY/skills/project-policy/SKILL.md" \
  > "$MISSINGPOLICY/skills/project-policy/SKILL.next"
mv "$MISSINGPOLICY/skills/project-policy/SKILL.next" "$MISSINGPOLICY/skills/project-policy/SKILL.md"
if bash "$MISSINGPOLICY/install.sh" --check >/dev/null 2>&1; then
  bad "install validation passed a project-policy missing a registered key"
else ok; fi

# 10) a later install retires files listed by the previous manifest but removed
# from the vendored tree, so legacy skills do not remain discoverable forever.
bash "$REPO/install.sh" >/dev/null 2>&1 || bad "clean reinstall before retirement test failed"
mkdir -p "$HOME/.claude/skills/legacy-only"
printf '%s\n' '---' 'name: legacy-only' 'description: retirement fixture' '---' \
  > "$HOME/.claude/skills/legacy-only/SKILL.md"
legacy_hash="$(shasum -a 256 "$HOME/.claude/skills/legacy-only/SKILL.md" | awk '{print $1}')"
jq --arg h "$legacy_hash" '.files["skills/legacy-only/SKILL.md"] = $h' \
  "$MANIFEST" > "$MANIFEST.next" && mv "$MANIFEST.next" "$MANIFEST"
if bash "$REPO/install.sh" >/dev/null 2>&1; then
  [ ! -f "$HOME/.claude/skills/legacy-only/SKILL.md" ] && ok \
    || bad "install did not retire a removed legacy skill file"
  jq -e '.files["skills/legacy-only/SKILL.md"] == null' "$MANIFEST" >/dev/null \
    && ok || bad "new manifest retained a retired legacy skill entry"
else
  bad "install failed during legacy retirement test"
fi

echo "install-skills tests: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
