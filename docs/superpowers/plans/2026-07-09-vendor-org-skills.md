# Vendoring the Ten Org Skills into the Repo — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vendor ten previously-external org skills into a new top-level `skills/` directory (modernized to current conventions), teach `install.sh` to install/validate/back-up/roll-back/manifest/`--check` them, prove it with a new sandbox install test, and update the README so a fresh clone installs cleanly on any machine.

**Architecture:** The repo's `skills/` tree mirrors the installed layout under `~/.claude/skills/` exactly — every file under `skills/<name>/<relpath>` copies to `~/.claude/skills/<name>/<relpath>`. The repo tree is itself the allowlist: only files meant to be installed exist there, so the installer needs no exclude rules. `install.sh` gains a repo-tree resolution path so a fresh machine passes validation for the skills the same run is about to install, plus nested-path backup/install/rollback, a skills manifest namespace, `--check` coverage, and three new pre-copy validations (SKILL.md presence + frontmatter, `name:` == directory, hash-identical shared references).

**Tech Stack:** Bash + `jq` + `shasum` (all already required by the installer); Markdown skill content. No new runtime dependencies. Per the human's SPEC GATE decision, the audit skill is vendored as prompt-only (SKILL.md + patterns.md) — **no Python anywhere**, so `python3` is not a dependency of this work.

## Global Constraints

Copied verbatim from the spec and the team's fixed rules; every task's requirements implicitly include these.

- **Builder may never install any package** (pip, npm, brew, or otherwise). Default to stdlib tooling. No `brew install`, no `pip install`.
- **Builder may never delete or move files via shell** (`rm`, `mv`, and equivalents). Exclusions happen by *not creating* the file in the repo tree; content that must change is overwritten in place via Edit/Write. (The `rm -f` inside `install.sh`'s own rollback paths is script *content* run by whoever executes the installer — it is authored via Write, never run by the builder as a shell command.)
- **No machine-specific paths** (`/Users/jay/...`) and no machine-local tool dependencies (claude-mem) anywhere under `skills/`.
- **No emojis** in any instruction or output template; use words (PASS/FAIL, CRITICAL/HIGH/MEDIUM, Wrong/Correct).
- **Every SKILL.md** has `name:` matching its directory and a trigger-worthy `description:`; filename is exactly `SKILL.md` (uppercase).
- **No time/effort estimates** introduced anywhere.
- **1Password auth is service-account only** (`OP_SERVICE_ACCOUNT_TOKEN` from `~/.op/service_account.token`, vault `ClaudeCodeAccess-Jay`); never desktop-app auth; never write secret values to disk.
- **The three human SPEC-GATE decisions are settled** (do not re-open):
  - audit-requirements-document → **Option B**: vendor a rewritten `SKILL.md` + cleaned `patterns.md` only; **drop the entire Python pipeline** (no `*.py`, no tests, no `__pycache__`, no `*.pyc`, no `integration_test_report_*.json`).
  - secure-secrets → **rework to service-account-only auth**, never write secrets to disk (remove the plaintext config-backup step and the desktop-auth/`brew install` steps), and add the missing `name:`/`description:` frontmatter.
  - writing-business-requirements → vendor **SKILL.md only**; leave out the `examples.md` stub and the three `*-subagent-prompt.md` files.
- **Done means committed:** a git commit of all new/changed files is part of the builder's done-definition (the user's commit-immediately rule). Each task ends by committing that task's deliverable.

## Source and target reference (read before starting)

Live source copies (author's machine) live under `~/.claude/skills/<name>/`. The builder reads each source file, applies the modernization changes below, and **writes** the result into the repo (`skills/<name>/...`). The builder never `cp`s from `~/.claude/skills/` — it reads with Read and writes with Write, because (a) the content is being modified during vendoring and (b) the repo tree is the canonical, modernized copy.

Complete per-skill vendoring allowlist (files that go into the repo) and exclusions (files that must NOT be created in the repo):

| Skill | Vendor into repo | Exclude (do not create in repo) |
|---|---|---|
| coding-standards | `SKILL.md`, `references/coding-standards.md` | `CLAUDE.md` |
| code-review | `SKILL.md`, `references/coding-standards.md` | `CLAUDE.md` |
| secure-secrets | `SKILL.md` (reworked) | `CLAUDE.md` |
| write-ticket | `SKILL.md` (modernized) | `temp/skill-improver-debug.log` (and `temp/`) |
| review-ticket | `SKILL.md` (modernized) | `CLAUDE.md` |
| task-verification | `SKILL.md` (minor cleanup) | `CLAUDE.md` |
| writing-business-requirements | `SKILL.md` | `examples.md`, `extract-coding-standards-subagent-prompt.md`, `capture-implementation-notes-subagent-prompt.md`, `document-architecture-decisions-subagent-prompt.md`, `CLAUDE.md` |
| audit-requirements-document | `SKILL.md` (rewritten from `skill.md`, Option B), `patterns.md` (cleaned) | `skill.md` (lowercase — replaced by SKILL.md), `extractor.py`, `test_extractor.py`, `file_operations.py`, `test_file_operations.py`, `verification.py`, `run_audit.py`, `tests/`, `__pycache__/`, `*.pyc`, `integration_test_report_*.json`, `testing-summary.md`, `pattern-validation-results.md` |
| plan-review | `SKILL.md` (modernized), `references/coding-standards.md` | (none present) |
| ux-to-ui-design | `SKILL.md` (verbatim) | (none present) |

Fourteen repo files result: 10 × `SKILL.md`, 3 × `references/coding-standards.md`, 1 × `audit-requirements-document/patterns.md`.

Cross-cutting modernization rules applied while writing each SKILL.md (spec section 4): proper frontmatter; exactly `SKILL.md`; no emojis (use words); no `/Users/jay/...` paths and no claude-mem dependency; no stale-artifact content; no time/effort estimates.

---

## Phase 1 — Vendor the ten skills into `skills/`

Each task reads the live source, applies its named changes, and writes the modernized file(s) into the repo. After Phase 1 the repo tree is the complete, modernized allowlist; Phase 2 wires the installer to it. Committing per skill keeps each reviewable in isolation.

### Task 1: Vendor coding-standards (KEEP, minor cleanup)

**Files:**
- Create: `skills/coding-standards/SKILL.md`
- Create: `skills/coding-standards/references/coding-standards.md`
- Read (source): `~/.claude/skills/coding-standards/SKILL.md`, `~/.claude/skills/coding-standards/references/coding-standards.md`

**Interfaces:**
- Produces: `skills/coding-standards/references/coding-standards.md` — this is the canonical copy; Tasks 2 and 9 must write byte-identical copies (hash-identity is enforced by the installer in Task 12). Read this file's exact bytes when creating the other two.

- [ ] **Step 1: Read the source SKILL.md and references file.** Read both source files in full.
- [ ] **Step 2: Write `skills/coding-standards/SKILL.md`.** Copy the source content verbatim EXCEPT: confirm `name: coding-standards` and a trigger-worthy `description:` are present in frontmatter (they are — leave as-is); confirm no emojis and no `/Users/jay` paths (none expected). Do NOT copy `CLAUDE.md`. Add nothing new.
- [ ] **Step 3: Write `skills/coding-standards/references/coding-standards.md`.** Copy the source references file verbatim, byte-for-byte. This is the DRY source for the other two copies.
- [ ] **Step 4: Verify hygiene.** Confirm the two new files contain no `CLAUDE.md` content, no emoji, no `/Users/jay` string, and the SKILL.md frontmatter `name:` equals `coding-standards`.
- [ ] **Step 5: Commit.**
```bash
git add skills/coding-standards/
git commit -m "feat(skills): vendor coding-standards (SKILL.md + references)"
```

### Task 2: Vendor code-review (KEEP, emoji strip)

**Files:**
- Create: `skills/code-review/SKILL.md`
- Create: `skills/code-review/references/coding-standards.md`
- Read (source): `~/.claude/skills/code-review/SKILL.md`, `~/.claude/skills/code-review/references/coding-standards.md`

**Interfaces:**
- Consumes: the byte-exact `references/coding-standards.md` produced in Task 1 — this copy must hash-match it. Source it from `skills/coding-standards/references/coding-standards.md` to guarantee identity.

- [ ] **Step 1: Read the source SKILL.md.** Read in full.
- [ ] **Step 2: Write `skills/code-review/SKILL.md`.** Copy source content EXCEPT: in the report template, replace every decorative checkmark/cross emoji with the plain words already implied — PASS / FAIL / CRITICAL. Confirm frontmatter `name: code-review` and a good `description:`. Do NOT copy `CLAUDE.md`.
- [ ] **Step 3: Write `skills/code-review/references/coding-standards.md` from Task 1's copy.** Read `skills/coding-standards/references/coding-standards.md` (the copy just vendored) and write its exact bytes here, so the two are hash-identical.
- [ ] **Step 4: Verify hygiene + hash identity.** Confirm no emoji remain in SKILL.md; confirm this references file is byte-identical to `skills/coding-standards/references/coding-standards.md` (e.g. compare with `shasum -a 256` on both — this is read-only verification, not a policy-blocked mutation).
- [ ] **Step 5: Commit.**
```bash
git add skills/code-review/
git commit -m "feat(skills): vendor code-review (emoji-stripped report template)"
```

### Task 3: Vendor secure-secrets (REWORK — security-critical)

**Files:**
- Create: `skills/secure-secrets/SKILL.md`
- Read (source): `~/.claude/skills/secure-secrets/SKILL.md`

**Interfaces:**
- Produces: a single self-contained `skills/secure-secrets/SKILL.md`. No references dir, no `CLAUDE.md`.

- [ ] **Step 1: Read the source SKILL.md in full.** Note the existing `allowed-tools` frontmatter and the four problem areas (plaintext backups, desktop-auth/brew, missing name/description, value-display/emoji/bulk transcript).
- [ ] **Step 2: Write `skills/secure-secrets/SKILL.md` with corrected frontmatter.** Add proper frontmatter: `name: secure-secrets`, and a `description:` covering BOTH uses — the interactive credential-migration workflow AND the always-on discipline (env-var references only; never write or echo secret values; the `op item create`/`op item edit` exception for passing values to the vault). Preserve the existing `allowed-tools` key.
- [ ] **Step 3: Rework Phase 1 to service-account-only auth.** Replace the desktop-app CLI-integration check and the `brew install` offer with: verify `op` exists on PATH and, if not, **report and stop — do not install**; authenticate via the service-account token (`OP_SERVICE_ACCOUNT_TOKEN` sourced from `~/.op/service_account.token`, vault `ClaudeCodeAccess-Jay`); and where a target vault is outside the service account's access, hand that specific step to the human rather than switching auth modes. State explicitly: never desktop-app auth.
- [ ] **Step 4: Remove the plaintext-backup step and its cleanup phase.** Delete the Phase 4 step that copies `~/.zshrc` etc. into a project `/reports/` folder, and the later "delete backups" cleanup. Add a one-line rationale in the workflow text: the verified 1Password entry IS the backup, because every credential is stored and verified via `op read` before it is removed from source — writing secrets to disk is forbidden without exception.
- [ ] **Step 5: Tighten value display, strip emojis, cut the transcript.** Make "value preview (first/last few chars only)" the ONLY permitted display form; remove any allowance to display full values "when necessary." Replace risk-level emojis (red/orange/yellow circles) with the words CRITICAL/HIGH/MEDIUM. Cut the ~700-line simulated conversation transcript down to one short worked example so the operative rules are not buried.
- [ ] **Step 6: Verify hygiene.** Confirm: frontmatter has `name: secure-secrets` and a two-use `description:`; no emoji; no `/Users/jay` literal (the service-account token path `~/.op/service_account.token` uses `~`, which is correct); no step writes a secret to disk; no `brew install`; previews-only display.
- [ ] **Step 7: Commit.**
```bash
git add skills/secure-secrets/
git commit -m "feat(skills): vendor secure-secrets reworked to service-account-only, no on-disk secrets"
```

### Task 4: Vendor write-ticket (MODERNIZE)

**Files:**
- Create: `skills/write-ticket/SKILL.md`
- Read (source): `~/.claude/skills/write-ticket/SKILL.md`

- [ ] **Step 1: Read the source SKILL.md in full.**
- [ ] **Step 2: Write `skills/write-ticket/SKILL.md` with the four modernization edits.**
  1. Remove the claude-mem dependency: replace "Search claude-mem for related work" with "search project docs and the scribe's status notes."
  2. Namespace the superpowers skill references inside generated tickets — `test-driven-development` → `superpowers:test-driven-development`, `brainstorming` → `superpowers:brainstorming`, `systematic-debugging` → `superpowers:systematic-debugging`, `writing-plans` → `superpowers:writing-plans`. Leave org-skill names bare.
  3. Strip decorative emojis from templates and anti-pattern headers (use plain words).
  4. Do NOT create `temp/` or `temp/skill-improver-debug.log`.
- [ ] **Step 3: Verify hygiene.** Confirm frontmatter `name: write-ticket` + good `description:` present; no emoji; no claude-mem reference; superpowers refs namespaced; no `temp/` artifact; no `/Users/jay`.
- [ ] **Step 4: Commit.**
```bash
git add skills/write-ticket/
git commit -m "feat(skills): vendor write-ticket (drop claude-mem, namespace superpowers refs)"
```

### Task 5: Vendor review-ticket (MODERNIZE — conditional subagent guidance)

**Files:**
- Create: `skills/review-ticket/SKILL.md`
- Read (source): `~/.claude/skills/review-ticket/SKILL.md`

- [ ] **Step 1: Read the source SKILL.md in full.**
- [ ] **Step 2: Write `skills/review-ticket/SKILL.md` with the modernization edits.**
  1. Same claude-mem removal as write-ticket ("search project docs and the scribe's status notes").
  2. Rewrite the "dispatch subagents via the Task tool" section CONDITIONALLY: "When the Task tool is available, delegate the focused lookups (for example an Explore-type dispatch). When it is not available (running as a dispatched agent, e.g. inside the ticketer), do the focused lookups inline and recommend decomposition to the orchestrator in the report instead of dispatching." Remove the hardcoded `Task(subagent_type="Explore")` / general-purpose-dispatch instructions as unconditional steps.
  3. Strip emojis from the report templates (warning/check/cross/recycle/pause symbols → plain words such as WARNING, PASS, FAIL, IN PROGRESS, BLOCKED as appropriate).
  4. Do NOT copy `CLAUDE.md`.
- [ ] **Step 3: Verify hygiene.** Confirm `name: review-ticket` + good `description:`; no emoji; no claude-mem; subagent guidance is conditional; no `/Users/jay`.
- [ ] **Step 4: Commit.**
```bash
git add skills/review-ticket/
git commit -m "feat(skills): vendor review-ticket (conditional subagent guidance, drop claude-mem)"
```

### Task 6: Vendor task-verification (KEEP, minor cleanup)

**Files:**
- Create: `skills/task-verification/SKILL.md`
- Read (source): `~/.claude/skills/task-verification/SKILL.md`

- [ ] **Step 1: Read the source SKILL.md in full.**
- [ ] **Step 2: Write `skills/task-verification/SKILL.md` with the two edits.**
  1. Strip emojis from templates (check/cross/warning → PASS / FAIL / PARTIAL — the words are already present alongside them).
  2. Tighten the hedge about `verification-before-completion` ("If this skill exists...") to state the real division of labor: task-verification for Asana subtasks; `superpowers:verification-before-completion` for any work unit (the verifier preloads both, so the skill exists).
  3. Do NOT copy `CLAUDE.md`. (The pytest-flavored illustrative examples stay — they illustrate verifying an arbitrary project, not tooling this repo runs.)
- [ ] **Step 3: Verify hygiene.** Confirm `name: task-verification` + good `description:`; no emoji; the verification-before-completion reference is namespaced and non-hedged; no `/Users/jay`.
- [ ] **Step 4: Commit.**
```bash
git add skills/task-verification/
git commit -m "feat(skills): vendor task-verification (emoji strip, firm up verification-before-completion split)"
```

### Task 7: Vendor writing-business-requirements (KEEP SKILL.md, prune directory)

**Files:**
- Create: `skills/writing-business-requirements/SKILL.md`
- Read (source): `~/.claude/skills/writing-business-requirements/SKILL.md`

- [ ] **Step 1: Read the source SKILL.md in full.**
- [ ] **Step 2: Write `skills/writing-business-requirements/SKILL.md`.** Copy the SKILL.md substance. Replace decorative cross/check markers in the before/after examples with the plain labels "Wrong:" / "Correct:" (already labeled — just drop the emoji). Confirm `name: writing-business-requirements` + good `description:`.
- [ ] **Step 3: Confirm exclusions.** Do NOT create `examples.md` (a TODO stub), the three `*-subagent-prompt.md` files, or `CLAUDE.md`. The SKILL.md must not reference any of them; if it does, remove those references.
- [ ] **Step 4: Verify hygiene.** Confirm the directory contains only `SKILL.md`; no emoji; no `/Users/jay`; no dangling references to the excluded files.
- [ ] **Step 5: Commit.**
```bash
git add skills/writing-business-requirements/
git commit -m "feat(skills): vendor writing-business-requirements (SKILL.md only, prune stubs)"
```

### Task 8: Vendor audit-requirements-document (REWRITE — Option B, prompt-only, NO Python)

**Files:**
- Create: `skills/audit-requirements-document/SKILL.md`
- Create: `skills/audit-requirements-document/patterns.md`
- Read (source): `~/.claude/skills/audit-requirements-document/skill.md` (lowercase), `~/.claude/skills/audit-requirements-document/patterns.md`

**Interfaces:**
- Produces: exactly two files. No `.py`, no `tests/`, no JSON reports, no historical run records.

- [ ] **Step 1: Read the source `skill.md` (lowercase) and `patterns.md` in full.** Note every `/Users/jay/...` absolute path and every reference to the Python modules, the grant-proposal test corpus, `run_audit.py`, `testing-summary.md`, `pattern-validation-results.md`, and the `integration_test_report_*.json` files.
- [ ] **Step 2: Write `skills/audit-requirements-document/SKILL.md` (uppercase) as a model-performed audit.** Rewrite the four-stage "automated" pipeline workflow into an audit the scribe performs directly: read the target document; apply the `patterns.md` catalog directly; produce a violation report with recommended destinations for misplaced content. State that the report must list which pattern categories were applied, so a human can spot-check (compensating for the lost deterministic re-scan). Remove ALL references to the Python modules, `run_audit.py`, the grant-proposal corpus, and the historical run-record files. Convert every `/Users/jay/.claude/skills/...` path to `~/.claude/skills/...` and drop grant-proposal test-corpus paths entirely. Ensure frontmatter `name: audit-requirements-document` and a trigger-worthy `description:` (the source description text is a fine starting point). Strip emojis from report templates.
- [ ] **Step 3: Write `skills/audit-requirements-document/patterns.md` (cleaned).** Copy the source patterns catalog, converting any `/Users/jay/...` paths to `~/...` or relative, removing grant-proposal-specific references, and stripping emojis. This is the human-readable catalog the SKILL.md tells the scribe to apply.
- [ ] **Step 4: Confirm exclusions.** The directory must contain ONLY `SKILL.md` and `patterns.md`. Do NOT create `skill.md` (lowercase), any `*.py`, `tests/`, `__pycache__/`, `*.pyc`, `integration_test_report_*.json`, `testing-summary.md`, or `pattern-validation-results.md`.
- [ ] **Step 5: Verify hygiene.** Confirm the directory has exactly two files, both emoji-free, with no `/Users/jay` literal and no reference to any dropped Python/artifact file; SKILL.md `name:` equals the directory name; filename is uppercase `SKILL.md`.
- [ ] **Step 6: Commit.**
```bash
git add skills/audit-requirements-document/
git commit -m "feat(skills): vendor audit-requirements-document prompt-only (Option B, no Python)"
```

### Task 9: Vendor plan-review (MODERNIZE)

**Files:**
- Create: `skills/plan-review/SKILL.md`
- Create: `skills/plan-review/references/coding-standards.md`
- Read (source): `~/.claude/skills/plan-review/SKILL.md`

**Interfaces:**
- Consumes: the byte-exact `references/coding-standards.md` from Task 1. Source it from `skills/coding-standards/references/coding-standards.md` to guarantee hash identity.

- [ ] **Step 1: Read the source SKILL.md in full.**
- [ ] **Step 2: Write `skills/plan-review/SKILL.md` with the substantive corrections.**
  1. Git guidance: replace "one commit" with "commits are logical units, at least one per task; each references the task."
  2. IaC tooling: replace "Use Terraform/Pulumi" with "org-approved IaC (SAM, CDK, Amplify); no manual console changes."
  3. Add the team's fixed constraints as checks: flag plan steps that install packages (forbidden — stdlib-first unless a dependency was explicitly pre-approved by the human) and plan steps that delete/move files via shell (forbidden — plan around, or overwrite in place via Edit/Write).
  4. Strip the few check/cross markers (use words). Confirm `name: plan-review` + good `description:`.
- [ ] **Step 3: Write `skills/plan-review/references/coding-standards.md` from Task 1's copy.** Read `skills/coding-standards/references/coding-standards.md` and write its exact bytes here (hash-identical, third copy).
- [ ] **Step 4: Verify hygiene + hash identity.** No emoji; git/IaC/constraint edits present; this references file byte-identical to the coding-standards copy (compare with `shasum -a 256`, read-only).
- [ ] **Step 5: Commit.**
```bash
git add skills/plan-review/
git commit -m "feat(skills): vendor plan-review (commit-per-task, org IaC, team fixed-constraint checks)"
```

### Task 10: Vendor ux-to-ui-design (KEEP AS-IS)

**Files:**
- Create: `skills/ux-to-ui-design/SKILL.md`
- Read (source): `~/.claude/skills/ux-to-ui-design/SKILL.md`

- [ ] **Step 1: Read the source SKILL.md in full.**
- [ ] **Step 2: Write `skills/ux-to-ui-design/SKILL.md` verbatim.** No content changes — it is already to current standards (correct frontmatter, no emoji, no machine paths, single self-contained file). Confirm those properties hold as you write.
- [ ] **Step 3: Verify hygiene.** `name: ux-to-ui-design` + description present; no emoji; no `/Users/jay`; single file.
- [ ] **Step 4: Commit.**
```bash
git add skills/ux-to-ui-design/
git commit -m "feat(skills): vendor ux-to-ui-design verbatim"
```

---

## Phase 2 — Wire the installer to the vendored skills

Now that `skills/` is the complete modernized allowlist, extend `install.sh` so a fresh clone resolves, installs, backs up, rolls back, manifests, and `--check`s the skills. **TDD note:** the installer behavior is proven by the sandbox test written in Task 11 *before* the installer code that satisfies it (Task 12). Task 11 writes the failing test; Task 12 makes it pass.

### Task 11: Write the failing sandbox install test

**Files:**
- Create: `tests/test_install_skills.sh`
- Read (for style): `tests/test_dispatch_guard.sh`, `install.sh`

**Interfaces:**
- Consumes: `install.sh` behavior as it WILL be after Task 12 — the test is written against the target contract and must FAIL until Task 12 lands.
- Produces: `tests/test_install_skills.sh`, wired into `install.sh`'s validation block in Task 12.

- [ ] **Step 1: Write `tests/test_install_skills.sh`.** Follow the existing suite style (`set -u`, `HERE="$(cd "$(dirname "$0")" && pwd)"`, PASS/FAIL counters, a final `PASS=/FAIL=` line, exit nonzero on any failure). The test builds a sandbox `HOME` in a temp dir and runs the real `install.sh` against it. Concretely it must:

```bash
#!/usr/bin/env bash
# tests/test_install_skills.sh — install the vendored skills into a sandbox HOME
# and verify resolution, install, manifest, --check OK, and drift detection.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$HERE/.."
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

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
  found="$(cd "$HOME/.claude/skills/$name" 2>/dev/null && ls | grep -x 'SKILL.md')"
  [ "$found" = "SKILL.md" ] && ok || bad "skill $name missing exact-name SKILL.md after install"
done
# every vendored file arrived at its mapped path
( cd "$REPO/skills" && find . -type f ) | while read -r rel; do
  rel="${rel#./}"
  [ -f "$HOME/.claude/skills/$rel" ] || echo "MISSINGFILE $rel"
done | grep -q MISSINGFILE && bad "a vendored skills file did not arrive at its mapped path" || ok

# 3) manifest has a skills/... entry with correct hash for every vendored file
MANIFEST="$HOME/.claude/agent-team-manifest.json"
miss=0
( cd "$REPO/skills" && find . -type f ) | while read -r rel; do
  rel="${rel#./}"; key="skills/$rel"
  want="$(shasum -a 256 "$REPO/skills/$rel" | awk '{print $1}')"
  got="$(jq -r --arg k "$key" '.files[$k] // empty' "$MANIFEST")"
  [ "$got" = "$want" ] || { echo "BADHASH $key"; }
done | grep -q BADHASH && bad "manifest missing/incorrect hash for a skills file" || ok

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
```

Note on the `rm -rf`/`rm -f`/`cp -R` calls above: they are lines of *test-script content* authored with the Write tool and executed by the test runner against a throwaway sandbox `HOME` — they are not shell commands the builder runs directly, so they do not collide with the no-delete/no-move policy. Never invoke `rm`/`mv`/`cp` from the builder's own Bash to accomplish this task; write them into the script only.

- [ ] **Step 2: Run the new test to confirm it FAILS.**
Run: `bash tests/test_install_skills.sh`
Expected: FAIL — the installer does not yet copy skills, so the ten-skills-present, manifest, and `--check` assertions fail (nonzero exit).
- [ ] **Step 3: Commit the failing test.**
```bash
git add tests/test_install_skills.sh
git commit -m "test(install): add failing sandbox install test for vendored skills"
```

### Task 12: Extend install.sh to install/validate/back-up/roll-back/manifest/check skills

**Files:**
- Modify: `install.sh` (resolve_skill 55-68; validation block ~22-47; backup 145-170; restore 172-186; cleanup_fresh 193-207; install 209-223; manifest 225-245; check mode 107-142; success line 247)

**Interfaces:**
- Consumes: the `skills/` tree from Phase 1; `tests/test_install_skills.sh` from Task 11 (added to the validation block here).
- Produces: an installer that copies every `skills/<name>/<relpath>` to `~/.claude/skills/<name>/<relpath>`, records each in the manifest under key `skills/<name>/<relpath>`, and covers them in `--check`.

- [ ] **Step 1: Add repo-tree resolution to `resolve_skill` for bare names.** In the `*)` (bare-name) arm, after the built-in whitelist check, resolve against the repo tree ahead of the installed fallback so a fresh machine passes for skills this run will install:
```sh
      case "$BUILTIN_SKILLS" in
        *" $1 "*) return 0 ;;
      esac
      [ -f "$REPO/skills/$1/SKILL.md" ] || [ -f "$HOME/.claude/skills/$1/SKILL.md" ]
```
The namespaced (`*:*`) arm and the situational-skill loop (line 96) are unchanged — `plan-review` and `ux-to-ui-design` now resolve via the repo check; `superpowers:brainstorming` still resolves via the plugin cache.
- [ ] **Step 2: Add the three pre-copy skills validations to the validation block** (after the existing hook/test validations, before the resolve loops so the repo tree is trusted). Insert:
```sh
# --- vendored skills validation (before anything is copied) ---
for d in "$REPO"/skills/*/; do
  name="$(basename "$d")"
  sm="$d/SKILL.md"
  [ -f "$sm" ] || fail "skills/$name has no SKILL.md"
  fm="$(awk '/^---$/{n++; next} n==1{print}' "$sm")"
  printf '%s\n' "$fm" | grep -qE '^name:' || fail "skills/$name/SKILL.md: missing frontmatter 'name:'"
  printf '%s\n' "$fm" | grep -qE '^description:' || fail "skills/$name/SKILL.md: missing frontmatter 'description:'"
  smname="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p')"
  [ "$smname" = "$name" ] || fail "skills/$name/SKILL.md: name '$smname' != directory '$name'"
done
# the three coding-standards.md copies must be hash-identical (DRY guard, 3.11)
cs_a="$REPO/skills/coding-standards/references/coding-standards.md"
cs_b="$REPO/skills/code-review/references/coding-standards.md"
cs_c="$REPO/skills/plan-review/references/coding-standards.md"
h_a="$(sha "$cs_a")"; h_b="$(sha "$cs_b")"; h_c="$(sha "$cs_c")"
[ "$h_a" = "$h_b" ] || fail "coding-standards.md differs: code-review copy diverged from coding-standards"
[ "$h_a" = "$h_c" ] || fail "coding-standards.md differs: plan-review copy diverged from coding-standards"
```
- [ ] **Step 3: Wire the new install test into the validation block** alongside the existing three:
```sh
bash "$REPO/tests/test_install_skills.sh" >/dev/null || fail "install-skills tests failed — run tests/test_install_skills.sh to see which"
```
Place this AFTER the skills-validation and resolve loops so it exercises a real installer. (It runs the installer against a sandbox HOME, so it does not touch the real `~/.claude`.) If a bootstrapping concern arises — the validation block running the very installer it is inside — Task 12's Step 12 self-check must confirm the sandbox test uses its own `HOME` and does not recurse; see the note there.
- [ ] **Step 4: Backup — track pre-existing skills files by relative path.** After the `PREEXISTING_GUARD` block, add a nested-path backup loop:
```sh
PREEXISTING_SKILLS=""
while IFS= read -r rel; do
  rel="${rel#./}"
  inst="$CLAUDE_DIR/skills/$rel"
  if [ -f "$inst" ]; then
    mkdir -p "$BACKUP/skills/$(dirname "$rel")"
    cp "$inst" "$BACKUP/skills/$rel"
    PREEXISTING_SKILLS="$PREEXISTING_SKILLS $rel"
  fi
done <<EOF
$(cd "$REPO/skills" && find . -type f)
EOF
```
Also ensure the backup dir and target skills root are created: add `"$CLAUDE_DIR/skills"` to the `mkdir -p` on the backup line (145).
- [ ] **Step 5: restore() — add a nested skills restore loop.** The existing `case "$(basename ...)"` cannot express nested paths, so add a separate loop restoring `$BACKUP/skills/` by relative path:
```sh
  if [ -d "$BACKUP/skills" ]; then
    while IFS= read -r b; do
      rel="${b#"$BACKUP"/skills/}"
      mkdir -p "$CLAUDE_DIR/skills/$(dirname "$rel")"
      cp "$b" "$CLAUDE_DIR/skills/$rel"
    done <<EOF
$(find "$BACKUP/skills" -type f 2>/dev/null)
EOF
  fi
```
- [ ] **Step 6: cleanup_fresh() — remove freshly installed skills files that had no pre-existing version.** Add:
```sh
  while IFS= read -r rel; do
    rel="${rel#./}"
    case " $PREEXISTING_SKILLS " in
      *" $rel "*) : ;;                                  # pre-existing; restore() handled it
      *) rm -f "$CLAUDE_DIR/skills/$rel" ;;             # freshly installed; revert to "not here"
    esac
  done <<EOF
$(cd "$REPO/skills" && find . -type f)
EOF
```
(Directories intentionally left in place — the non-destructive guarantee only manages files this installer created; leaving an empty dir is harmless and avoids touching anything unmanaged.)
- [ ] **Step 7: Install — copy every skills file with nested-path support.** After the rates-file copy and before the chmods, add:
```sh
while IFS= read -r rel; do
  rel="${rel#./}"
  mkdir -p "$CLAUDE_DIR/skills/$(dirname "$rel")" || { restore; cleanup_fresh; fail "cannot create skills target dir for $rel; rolled back"; }
  if ! cp "$REPO/skills/$rel" "$CLAUDE_DIR/skills/$rel"; then restore; cleanup_fresh; fail "skill copy failed for $rel; rolled back"; fi
done <<EOF
$(cd "$REPO/skills" && find . -type f)
EOF
```
- [ ] **Step 8: Manifest — record each skills file under key `skills/<relpath>`.** In the manifest generation block, add a third producer alongside agents and hooks:
```sh
  while IFS= read -r rel; do rel="${rel#./}"; printf 'skills/%s\t%s\n' "$rel" "$(sha "$REPO/skills/$rel")"; done <<EOF
$(cd "$REPO/skills" && find . -type f)
EOF
```
Insert this inside the `{ ... }` group that feeds `jq`, after the hooks loop.
- [ ] **Step 9: --check — add a skills case arm and extend NEW detection.** In the manifest-walk `case "$rel"`, add before the catch-all:
```sh
      skills/*) inst="$CLAUDE_DIR/skills/${rel#skills/}" ;;
```
The existing MISSING / DRIFT / REMOVED / STALE comparisons then apply unchanged. After the `agents/*.md` NEW-detection loop, add a skills NEW-detection loop:
```sh
  while IFS= read -r rel; do
    rel="skills/${rel#./}"
    jq -e --arg k "$rel" '.files[$k] != null' "$MANIFEST" >/dev/null \
      || { echo "check: NEW — $rel exists in the repo but was never installed"; drift=1; }
  done <<EOF
$(cd "$REPO/skills" && find . -type f)
EOF
```
- [ ] **Step 10: Update the final success line** (247) to report the skills count:
```sh
echo "install: OK — 10 agents + 10 skills installed, policy hook + cost hook installed, build $COMMIT recorded, backup at $BACKUP"
```
- [ ] **Step 11: Run `bash -n install.sh` to confirm the script parses.**
Run: `bash -n install.sh`
Expected: no output, exit 0.
- [ ] **Step 12: Run the new install test and confirm it now PASSES.**
Run: `bash tests/test_install_skills.sh`
Expected: `install-skills tests: PASS=<n> FAIL=0`, exit 0. If the validation block's call to `test_install_skills.sh` causes recursion or slowness, confirm the test exports its own sandbox `HOME` before invoking `install.sh` (it does, Task 11 Step 1) so the inner install cannot re-enter the outer test — the inner installer's validation block will itself try to run the test with the sandbox HOME already set; guard against infinite recursion by having the test set an env var (e.g. `export AGENT_TEAM_SKIP_INSTALL_TEST=1`) that the validation block honors:
```sh
[ -n "${AGENT_TEAM_SKIP_INSTALL_TEST:-}" ] || bash "$REPO/tests/test_install_skills.sh" >/dev/null || fail "install-skills tests failed — run tests/test_install_skills.sh to see which"
```
and have the test set `AGENT_TEAM_SKIP_INSTALL_TEST=1` before its own `bash install.sh` invocations (add `export AGENT_TEAM_SKIP_INSTALL_TEST=1` near the top of the test). This is a settled design fix (recursion is unavoidable otherwise); implement it in both files in this step.
- [ ] **Step 13: Run the existing suites to confirm no regression.**
Run: `bash tests/test_policy_hooks.sh && bash tests/test_cost_hook.sh && bash tests/test_dispatch_guard.sh`
Expected: each prints its PASS/FAIL line with FAIL=0 and exits 0.
- [ ] **Step 14: Run a real install and `--check` on this machine.**
Run: `bash install.sh && bash install.sh --check`
Expected: install prints `install: OK — 10 agents + 10 skills installed ...`; `--check` prints `check: OK`.
- [ ] **Step 15: Commit.**
```bash
git add install.sh tests/test_install_skills.sh
git commit -m "feat(install): install/validate/backup/rollback/manifest/check vendored skills"
```

---

## Phase 3 — Documentation

### Task 13: Update README.md

**Files:**
- Modify: `README.md` (dependency item 3 ~150-154; validation bullets in the install description; drift-detection section ~163-178; "How to change the team" ~180-187; `.gitignore` note)
- Read: `README.md`, `.gitignore` (if present)

- [ ] **Step 1: Rewrite dependency-list item 3** (~150-154). New text: the ten org skills are no longer an external machine dependency — they are vendored under `skills/` in the repo and installed by `install.sh` into `~/.claude/skills/`. The remaining external skill dependency shrinks to the superpowers plugin (plus client built-ins, already documented). The installer still resolves every reference and fails loudly on anything missing — now only plugin/built-in gaps rather than the org skills.
- [ ] **Step 2: Extend the install/validation description** to mention the new skills validation (SKILL.md presence, `name:`/`description:` frontmatter, `name:` == directory, hash-identical shared `references/coding-standards.md`, the sandbox install-test suite) and the skills copy/backup/rollback behavior.
- [ ] **Step 3: Update the drift-detection section** (~163-178) to state that skills files are manifest-tracked and `--check` covers them with the same DRIFT/STALE/MISSING/NEW/REMOVED semantics as agents and hooks.
- [ ] **Step 4: Update "How to change the team"** (~180-187) to add: skill edits are made under `skills/` in the repo and installed via `install.sh` — never by editing `~/.claude/skills/` directly, which `--check` flags as DRIFT.
- [ ] **Step 5: Ensure `.gitignore` ignores nothing that would hide vendored skills.** Read `.gitignore`. Since Option B vendors NO Python, no `__pycache__/`/`*.pyc` rule is required for this work; if such a rule already exists it is harmless — leave it. Do NOT add ignore rules that would exclude any file under `skills/`. (This step is a verification, not necessarily an edit.)
- [ ] **Step 6: Verify.** Re-read the changed README sections; confirm they describe vendored+installed skills, the new validations, and drift coverage, with no stale "external dependency" claim for the org skills.
- [ ] **Step 7: Commit.**
```bash
git add README.md .gitignore
git commit -m "docs(readme): skills are vendored/installed, not an external dependency; drift covers skills"
```

---

## Acceptance criteria (verifier-checkable — from spec section 7)

1. **Fresh-machine install:** `bash tests/test_install_skills.sh` passes — sandbox HOME with empty `~/.claude/skills/` and stubbed plugin cache, `bash install.sh` exits 0, all ten skills installed.
2. **All ten resolve + uppercase SKILL.md:** implicit in (1); additionally each installed skill has an exact-name `SKILL.md` verified by exact-name listing (so a case-insensitive filesystem cannot mask a lowercase file).
3. **Check reports OK:** `bash install.sh --check` exits 0 and prints `check: OK` immediately after install — in the sandbox test and on this machine.
4. **Drift detected:** edited installed file → DRIFT (nonzero), removed file → MISSING (nonzero), repo edit without reinstall → STALE (nonzero), each naming the file.
5. **Existing suites still pass:** `tests/test_policy_hooks.sh`, `tests/test_cost_hook.sh`, `tests/test_dispatch_guard.sh` all pass unchanged.
6. **Vendored hygiene:** no `__pycache__`, `*.pyc`, `*.log`, `CLAUDE.md`, `integration_test_report_*.json`, `testing-summary.md`, `pattern-validation-results.md`, or `/Users/jay` string anywhere under `skills/`; every SKILL.md has `name:` and `description:` with `name:` == directory; the three `references/coding-standards.md` copies are hash-identical.
7. **No Python:** under Option B this is the operative form — the audit skill directory contains only `SKILL.md` and `patterns.md`; there is no `.py`/`tests/`/`pytest` anywhere; the repo's shell test suites in (1), (4), (5) are the "tests still pass."
8. **Real machine:** on this machine, `bash install.sh` exits 0 and `bash install.sh --check` reports OK against the new manifest (which now includes skills entries).

## Done-definition

All thirteen tasks committed (each task commits its own deliverable, per the commit-immediately rule). The branch's final state: `skills/` holds fourteen vendored files, `install.sh` and `tests/test_install_skills.sh` are updated, README reflects the new reality, and both `bash install.sh` and `bash install.sh --check` succeed on this machine. Hand off per the writing-plans execution-choice prompt (subagent-driven recommended).

## Self-review notes (architect, completed)

- **Spec coverage:** every spec section maps to a task — 3.1-3.11 → Tasks 1-10 + the Task 12 hash-identity check; 5.2 resolve_skill → Task 12 Step 1; 5.3 backup/install/rollback → Task 12 Steps 4-7; 5.4 manifest/--check → Task 12 Steps 8-9; 5.5 test → Tasks 11-12; section 6 README → Task 13; section 7 acceptance → the criteria block above. The three gate decisions are pinned in Global Constraints and Tasks 3, 7, 8.
- **Placeholder scan:** no TBD/TODO/"handle edge cases"; every code step shows the exact bash. Content edits name the precise substitution.
- **Type/name consistency:** manifest key form `skills/<relpath>`, `--check` arm `skills/*) inst="$CLAUDE_DIR/skills/${rel#skills/}"`, and the copy loop's `$CLAUDE_DIR/skills/$rel` all agree; `PREEXISTING_SKILLS` membership uses the same relative-path token throughout.
- **Resolved-not-escalated fix:** the validation block running `test_install_skills.sh` which itself runs `install.sh` is genuine unbounded recursion. The spec's own 5.5 intent ("wired into install.sh's validation block like the existing three suites") plus the fail-loud principle settle the fix without a value judgment: gate the inner run behind `AGENT_TEAM_SKIP_INSTALL_TEST` (Task 12 Step 12). Recorded here for the scribe's status note.
