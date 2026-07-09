# Vendoring the Ten Org Skills into the Repo — Design Spec

**Date:** 2026-07-09
**Status:** Draft for human gate (design only; implementation plan is a separate, later dispatch)
**Author:** architect

## 1. Problem

A fresh clone of this repo on a new machine fails `bash install.sh` because the agent
definitions reference ten "org skills" that exist only in the original author's personal
`~/.claude/skills/` and were never checked into the repo. `install.sh` (the `resolve_skill`
function, lines 55–68, plus the frontmatter loop at 70–90 and the situational-skill loop at
96–98) resolves every bare `skills:` entry against `~/.claude/skills/<name>/SKILL.md` and
fails loudly when one is missing — correctly, but unrecoverably on a machine that never had
the skills.

**Goal:** vendor the ten skills into the repo, have `install.sh` install them into
`~/.claude/skills/`, record them in the manifest, and cover them with `--check` drift
detection — after first bringing each skill up to present-day quality, because they were
written some time ago against older conventions.

## 2. Scope and non-goals

**In scope:** the ten org skills below; `install.sh` install/validate/backup/rollback/
manifest/`--check` changes for them; README updates; a sandboxed install test.

**Out of scope:** `superpowers:*` skills and built-in skills (`verify`, `run`, etc.) — they
come from the plugin cache or the client and are already handled; any change to agent
definitions, policy hooks, or the cost hook; any edit to the live copies under
`~/.claude/skills/` (the vendored, modernized copies become canonical and get installed over
them).

**Skill-to-agent mapping (from `agents/*.md` frontmatter):**

| Skill | Used by |
|---|---|
| coding-standards | builder (preload) |
| code-review | reviewer (preload) |
| secure-secrets | builder, ops (preload) — SECURITY-CRITICAL |
| write-ticket, review-ticket | ticketer (preload) |
| task-verification | ticketer, verifier (preload) |
| writing-business-requirements, audit-requirements-document | scribe (preload) |
| plan-review, ux-to-ui-design | architect (situational, via Skill tool) |

## 3. Per-skill review

Review basis: today's skill-authoring standards (proper `name`/`description` frontmatter,
self-contained directory, no machine-specific paths), this user's global conventions (no
emojis in output, security rules, service-account-only 1Password auth, config in config
files, stdlib-first tooling), and the fixed team constraints (builder can never install
packages or delete/move files via shell).

### 3.1 coding-standards — KEEP, minor cleanup

Well-structured, tool-agnostic, correct frontmatter, no stale model or tool references.
Content (TDD, ≥90% coverage, logging security, IaC) matches current org practice.

Changes:
- Exclude `CLAUDE.md` from the vendored copy — it is an auto-generated claude-mem activity
  log, machine-specific noise, not part of the skill.
- Vendor `references/coding-standards.md` as-is (see 3.11 on the three duplicate copies).

### 3.2 code-review — KEEP, minor cleanup

Systematic nine-section checklist with severity classification; aligned with
coding-standards; correct frontmatter; nothing stale. Held to extra scrutiny as requested:
the security section (secrets in commits, log hygiene, error sanitization, input validation)
is accurate and consistent with the global security rules. No changes to substance.

Changes:
- Exclude `CLAUDE.md` (claude-mem artifact).
- Strip the handful of decorative checkmark/cross emojis from the report template in favor
  of plain PASS/FAIL/CRITICAL words (cross-cutting rule, section 4).

### 3.3 secure-secrets — NEEDS REWORK (security-critical)

The workflow spine (discover → confirm per credential → store in 1Password → test retrieval
via `op read` → only then remove from source → rotation plan) is sound. Four problems, two
of them direct violations of the user's global security rules:

1. **Plaintext secret backups.** Phase 4 copies `~/.zshrc` etc. — files containing live
   secrets — into a project `/reports/` folder as "temporary safety nets". That is writing
   secrets to disk, which the global rules forbid without exception. The safety-net argument
   is also redundant: by the skill's own ordering, every credential is already stored and
   verified in 1Password before it is removed from the source file — the vault entry IS the
   backup. Rework: remove the backup step and the later "delete backups" cleanup phase
   entirely.
2. **Desktop-app auth.** Phase 1 checks desktop-app CLI integration (`Settings > Developer >
   Integrate with 1Password CLI`) and offers to `brew install` the CLI. Global rule:
   service-account auth only (`OP_SERVICE_ACCOUNT_TOKEN` from `~/.op/service_account.token`,
   vault `ClaudeCodeAccess-Jay`), never desktop-app auth. Also, agents on this team can
   never install packages, so the `brew install` path is dead. Rework Phase 1: verify `op`
   exists (report and stop if not — do not install), authenticate via the service-account
   token, and where a target vault is outside the service account's access, hand that
   specific step to the human instead of switching auth modes.
3. **Missing skill frontmatter.** The file has `allowed-tools` frontmatter but no `name:` or
   `description:` keys, so the client falls back to the H1 and the skill's trigger
   description degrades to "Secure Secrets Skill". Rework: proper frontmatter with a
   trigger-worthy description covering both uses — the interactive migration workflow and
   the always-on discipline (env-var references only, never write/echo secret values, the
   `op item create` exception).
4. **Displaying values / emojis / bulk.** "Value preview (first/last few chars only)" should
   be the ONLY permitted display form — the current text also allows displaying full values
   "when necessary". Tighten to previews-only. Strip the risk-level emojis (🔴🟠🟡→
   CRITICAL/HIGH/MEDIUM text). The ~700-line file is dominated by a simulated conversation
   transcript; cut it to a short worked example so the operative rules are not buried.

### 3.4 write-ticket — MODERNIZE

Strong decomposition discipline (SoC subtasks, verifiable acceptance criteria, dependencies,
mandatory Skills-to-Use sections). Correct frontmatter.

Changes:
- Remove the claude-mem dependency ("Search claude-mem for related work") — claude-mem is a
  machine-local tool, not a team dependency; replace with "search project docs and the
  scribe's status notes".
- Skill names referenced inside generated tickets ("test-driven-development",
  "brainstorming", "systematic-debugging", "writing-plans") are superpowers plugin skills;
  write them namespaced (`superpowers:test-driven-development` etc.) so executors resolve
  them, while org skills stay bare.
- Strip decorative emojis from templates and anti-pattern headers.
- Exclude `temp/skill-improver-debug.log` from vendoring (debug artifact).

### 3.5 review-ticket — MODERNIZE

Good reconnaissance-before-execution structure with an explicit supervisor report. Correct
frontmatter.

Changes:
- Same claude-mem removal as write-ticket.
- The "dispatch subagents via the Task tool" guidance (`Task(subagent_type="Explore")`,
  general-purpose dispatch for write-ticket) is inoperable when this skill runs inside the
  ticketer, which is itself a dispatched subagent without the Task tool — and the team's
  dispatch-guard hook polices dispatches anyway. Rewrite that section conditionally: "when
  the Task tool is available, delegate...; when it is not (running as a dispatched agent),
  do the focused lookups inline and recommend decomposition to the orchestrator in the
  report instead of dispatching."
- Strip emojis from the report templates (⚠️/✅/❌/🔄/⏸️ → plain words).
- Exclude `CLAUDE.md` (claude-mem artifact).

### 3.6 task-verification — KEEP, minor cleanup

Evidence-before-completion discipline, concrete anti-patterns, solid report template.
Correct frontmatter. Its examples use pytest, but those are illustrations of verifying an
arbitrary project, not tooling this repo runs — acceptable.

Changes:
- Strip emojis from templates (✅/❌/⚠️ → PASS/FAIL/PARTIAL — the words are already there).
- Tighten the hedge about `verification-before-completion` ("If this skill exists...") —
  it does exist and the verifier preloads both; state the actual division: task-verification
  for Asana subtasks, superpowers:verification-before-completion for any work unit.
- Exclude `CLAUDE.md` (claude-mem artifact).

### 3.7 writing-business-requirements — KEEP SKILL.md, prune the directory

The SKILL.md is genuinely good: BABOK v3 / IEEE 830 grounded, atomic/testable/unambiguous
discipline, prohibited-language catalog, before/after examples. Keep its substance.

Changes:
- Exclude `examples.md` — it is an explicit TODO stub ("Examples to be added"); the SKILL.md
  already contains real examples.
- Exclude the three `*-subagent-prompt.md` files — they are not referenced by SKILL.md
  (they only reference each other) and belong to an older Asana-based extraction workflow
  superseded by the audit-requirements-document skill. NOTE for the gate: these files exist
  nowhere else; excluding them from vendoring means they never reach a new machine. I judge
  them retired; the human can overrule.
- Exclude `CLAUDE.md` (claude-mem artifact).
- Strip decorative ❌/✅ markers in favor of "Wrong:"/"Correct:" labels (they are already
  labeled; the emojis are redundant).

### 3.8 audit-requirements-document — NEEDS REWORK (largest item; gate decision required)

Two findings before the main decision:

- **The file is `skill.md`, lowercase.** `resolve_skill` checks for `SKILL.md`; it only
  resolves on this machine because APFS is case-insensitive. On any case-sensitive
  filesystem the skill silently fails to resolve. The vendored file must be `SKILL.md`.
- **Machine-specific absolute paths** (`/Users/jay/.claude/skills/...`,
  `/Users/jay/Code/corporate/python/grant-proposal/...`) appear in `skill.md` and
  `patterns.md`. All must become `~/.claude/skills/...` or relative references, and the
  grant-proposal test-corpus references must go.

The main issue is the Python pipeline. Reading all modules end-to-end shows it is an
internally inconsistent half-integration:

- Three incompatible pattern-dictionary shapes: `extractor.apply_patterns` expects
  `{category: {name: regex}}`; `run_audit.load_patterns` produces
  `{category: {"pattern": regex, "category": str}}` (so the literal strings "pattern" and
  category names get compiled as regexes); `verification.verify_no_violations` expects
  `{category: [regex, ...]}`.
- Category-name mismatch: `run_audit` emits `technology_specific`, `extractor` matches
  `technology_specifics` — those violations silently fall through to the default type.
- `extract_content` never sets the `destination` key that `run_audit` and
  `verification.verify_destination_content` read — destinations always come out "unknown"
  (confirmed by the skill's own `testing-summary.md`: "All items mapped to unknown").
- `run_audit.load_patterns` hardcodes a simplified pattern set and ignores `patterns.md`
  ("For now use simplified version") — config not in config.
- `file_operations` creates a `temp/` directory in whatever the current working directory
  is, and `Path.replace` from that temp dir to an arbitrary destination can cross
  filesystems and fail.
- `run_audit.py` writes `integration_test_report_*.json` into the skill directory itself
  (three such artifacts are sitting there now).
- Tests are pytest-based (`import pytest`, `tmp_path` fixtures). The team's builder can
  never install pytest; the fixed constraint is stdlib `unittest`.

**Option A — full repair.** Vendor the Python; fix the wiring (one canonical pattern shape,
sourced from a new machine-readable `patterns.json` with `patterns.md` remaining the human
documentation; destinations actually propagated; temp files via `tempfile` in the
destination's directory; reports to stdout or a caller-specified path); convert all three
test files from pytest to stdlib `unittest`. Meaningful builder effort; yields a
deterministic regex audit tool.

**Option B — prompt-only vendoring (RECOMMENDED).** Vendor a rewritten `SKILL.md` plus
`patterns.md` (cleaned); drop the Python modules from the vendored copy. Rewrite the
SKILL.md's four-stage "automated" workflow as a model-performed audit: the scribe reads the
document, applies the `patterns.md` catalog directly, and produces the violation report with
recommended destinations. Rationale: (1) the automation was never actually wired together —
`run_audit.py` is self-described as an integration test script with hardcoded simplified
patterns, and the model performs this pattern-recognition task natively and better with
context; (2) in team use the scribe's write lane is docs-only, so the pipeline's cross-file
extraction into `.claude/rules/` and `tests/` could not run under policy anyway — the skill's
real output is a report with recommendations; (3) far smaller vendored/drift surface and no
Python or test-runner machine dependency. Cost: loses deterministic re-scan verification;
the audit report should say which patterns were applied so a human can spot-check.

Excluded from vendoring under either option: `__pycache__/`, `*.pyc`,
`integration_test_report_*.json`, `testing-summary.md`, `pattern-validation-results.md`
(historical run records tied to the author's grant-proposal project; SKILL.md references to
them are removed in the rewrite). Emojis stripped from report templates.

### 3.9 plan-review — MODERNIZE

Deliberately telegraphic checklist; the shape is right for a gate skill. Three substantive
corrections:

- **Git guidance conflicts with team discipline.** "One commit" contradicts the
  frequent-commits, commit-per-task discipline of `superpowers:writing-plans` that every
  plan here follows. Fix: "commits are logical units, at least one per task; each references
  the task."
- **IaC tooling is wrong for this org.** "Use Terraform/Pulumi" — the deployer's lanes are
  SAM, Amplify, and CDK. Fix: "org-approved IaC (SAM, CDK, Amplify); no manual console
  changes."
- **Add the team's fixed constraints as checks.** The architect invokes this skill to
  validate plans for THIS team, so it should catch: plan steps that install packages
  (forbidden — stdlib-first unless a dependency was explicitly pre-approved by the human)
  and plan steps that delete/move files via shell (forbidden — plan around, or overwrite
  in place via Edit/Write).
- Keep `references/coding-standards.md` (see 3.11). Strip the few ✅/❌ markers.

### 3.10 ux-to-ui-design — KEEP AS-IS

Clearly written to current standards: correct frontmatter, one-way UX→UI reasoning,
state/viewport analysis, accessibility floor, worked example, no emojis, no stale
references, no machine-specific paths, single self-contained file. Vendor verbatim.

### 3.11 The triplicated references/coding-standards.md

`coding-standards`, `code-review`, and `plan-review` each carry
`references/coding-standards.md`; all three are currently 685 lines and byte-identical in
spot checks. Keep three copies — installed skills must stay self-contained under
`~/.claude/skills/<name>/`, and a shared install source would break the "repo mirrors
installed layout" property that keeps drift detection simple. To protect DRY, `install.sh`
validation gains one cheap check: the three vendored copies must have identical SHA-256
hashes, failing the install with a message naming the divergent copy. An edit to the
standards is then necessarily made in all three (a mechanical, verifiable act) or the
install fails loudly.

## 4. Cross-cutting modernization rules

Applied uniformly during vendoring (the vendored copy is the modernized version; live copies
under `~/.claude/skills/` are then overwritten by the installer):

1. **Frontmatter:** every SKILL.md has `name:` matching its directory and a trigger-worthy
   `description:`. (Only secure-secrets fails this today.)
2. **Filename:** exactly `SKILL.md`. (Only audit-requirements-document fails this today.)
3. **No emojis** in any instruction or output template; use words (PASS/FAIL, CRITICAL/HIGH/
   MEDIUM, Wrong/Correct).
4. **No machine-specific paths** (`/Users/jay/...`) and no references to machine-local tools
   (claude-mem) as dependencies.
5. **No stale-artifact files vendored:** `CLAUDE.md` claude-mem logs, `__pycache__/`,
   `*.pyc`, `temp/`, `*.log`, `integration_test_report_*.json`, historical test-run records,
   TODO stubs, orphaned files unreferenced by their SKILL.md.
6. **Stdlib-first tooling:** any vendored Python tests use `unittest`, never pytest
   (relevant only if Option A is chosen for 3.8).
7. **No time/effort estimates** introduced anywhere.

Exclusion is implemented by curation, not by installer logic: only files meant to be
installed are placed in the repo tree, so the repo tree itself is the allowlist and
`install.sh` needs no exclude rules.

## 5. Vendoring design

### 5.1 Repo layout

Top-level `skills/` directory mirroring the installed layout exactly:

```
skills/
  coding-standards/SKILL.md
  coding-standards/references/coding-standards.md
  code-review/SKILL.md
  code-review/references/coding-standards.md
  secure-secrets/SKILL.md
  write-ticket/SKILL.md
  review-ticket/SKILL.md
  task-verification/SKILL.md
  writing-business-requirements/SKILL.md
  audit-requirements-document/SKILL.md
  audit-requirements-document/patterns.md
  audit-requirements-document/...        # plus patterns.json, *.py, tests/ iff Option A
  plan-review/SKILL.md
  plan-review/references/coding-standards.md
  ux-to-ui-design/SKILL.md
```

Install rule: every file under `skills/` copies to the same relative path under
`~/.claude/skills/`. One directory of repo truth, one copy loop, one manifest namespace.

### 5.2 resolve_skill contract and change

Contract the vendored skills must satisfy (unchanged for consumers): a bare `skills:`
frontmatter entry `<name>` resolves iff `~/.claude/skills/<name>/SKILL.md` exists after
install; namespaced entries resolve against the plugin cache; built-ins by whitelist.

Change: because validation runs before anything is copied, a fresh machine would still fail
resolution for the ten skills the very install is about to provide. `resolve_skill` gains a
repo-skills check ahead of the installed-skills fallback for bare names:

```sh
[ -f "$REPO/skills/$1/SKILL.md" ] || [ -f "$HOME/.claude/skills/$1/SKILL.md" ]
```

Fail-loud behavior is preserved for any bare skill that is neither vendored nor already
installed. The situational-skill loop (line 96) needs no change — `plan-review` and
`ux-to-ui-design` now resolve via the repo check, `superpowers:brainstorming` still resolves
via the plugin cache (which remains a genuine external machine dependency).

New validation, alongside the existing checks and before any copying:
- every `skills/*/` directory in the repo contains a `SKILL.md` whose frontmatter has
  `name:` and `description:` and whose `name:` equals the directory name;
- the three `references/coding-standards.md` copies are hash-identical (3.11);
- (Option A only) every vendored `.py` passes `python3 -m py_compile`, making `python3` a
  documented machine dependency — another reason Option B is preferred.

### 5.3 Backup, install, rollback

Follows the existing pattern, extended to nested paths:

- **Backup:** for each repo skills file whose installed counterpart exists, copy it to
  `$BACKUP/skills/<same relative path>` (backup gains subdirectories; today it is flat).
  Track pre-existing vs fresh per relative path, as `PREEXISTING_AGENTS` does today.
- **Install:** create target directories, copy every repo skills file. Any failure triggers
  the existing restore-then-cleanup sequence.
- **restore():** additionally walks `$BACKUP/skills/` restoring by relative path (the
  current basename `case` statement cannot express nested paths, so skills restore is a
  separate loop, not new `case` arms).
- **cleanup_fresh():** additionally removes freshly created skills files that had no
  pre-existing version, so a failed fresh install still reverts to "nothing installed".
- **Non-destructive guarantee unchanged:** the installer never deletes anything it does not
  manage; a file that exists under an installed skill directory but not in the repo (e.g.
  the old claude-mem `CLAUDE.md` logs on this machine) is left alone.

(`rm -f` inside the installer's rollback paths is script content executed by whoever runs
`install.sh` — typically the human; it is not an agent shell command and does not collide
with the builder's no-delete policy. The builder authors the script via Edit/Write and never
needs to run `rm`/`mv` itself.)

### 5.4 Manifest and --check

- Manifest `files` map gains one entry per vendored skills file, keyed
  `skills/<name>/<relative path>` with its SHA-256, generated by walking `$REPO/skills`
  (same `find`-and-`sha` style as agents/hooks today).
- `--check` mapping gains one `case` arm:
  `skills/*) inst="$CLAUDE_DIR/skills/${rel#skills/}" ;;` — after which the existing
  MISSING / DRIFT / REMOVED / STALE comparisons apply unchanged to skills files.
- The NEW detection loop (repo file never installed) is extended to walk `$REPO/skills`
  files exactly as it walks `agents/*.md` today.
- The final success line reports the skills count alongside agents and hooks.

### 5.5 Testing the installer

New `tests/test_install_skills.sh`, same style as the existing suites: build a sandbox
`$HOME` containing an empty `.claude/skills/`, a stub plugin cache with
`superpowers/<ver>/skills/{brainstorming,test-driven-development,verification-before-completion,writing-plans,...}/SKILL.md`
placeholders (whatever the agent frontmatter requires to resolve), and `jq` available; then
assert:

1. `bash install.sh` exits 0 against the sandbox HOME.
2. All ten skills exist under the sandbox `~/.claude/skills/` with a `SKILL.md` each, and
   every vendored file arrived at its mapped path.
3. The manifest contains a `skills/...` entry with a correct hash for every vendored file.
4. `bash install.sh --check` exits 0 and prints OK.
5. After appending a byte to one installed skill file, `--check` exits nonzero and names it
   DRIFT; after removing it (within the test sandbox), `--check` names it MISSING.
6. A repo skills directory with no SKILL.md (constructed in a temp copy of the repo tree)
   fails validation before anything is copied.

This test is wired into `install.sh`'s validation block like the existing three suites.

## 6. Documentation updates (README.md)

- **"Deploying to another machine" item 3 (lines ~150–154):** rewrite. The org skills are no
  longer an external machine dependency; the external dependency shrinks to the superpowers
  plugin (plus the client built-ins, already documented). New text states that the ten org
  skills are vendored under `skills/` and installed by `install.sh` into
  `~/.claude/skills/`, and that the installer still resolves every reference and fails
  loudly on anything missing (now only plugin/built-in gaps).
- **"How to install" validation bullets:** add the skills validation (SKILL.md presence,
  frontmatter, hash-identical shared references, install-test suite) and the skills
  copy/backup behavior to the existing description.
- **"Drift detection" section:** note that skills files are manifest-tracked and `--check`
  covers them with the same DRIFT/STALE/MISSING semantics.
- **"How to change the team" section:** add that skill edits are made under `skills/` in the
  repo and installed — never by editing `~/.claude/skills/` directly, which `--check` will
  flag as DRIFT.
- **.gitignore:** ensure `__pycache__/` and `*.pyc` are ignored if Option A vendors Python.

## 7. Acceptance criteria (verifier-checkable)

1. **Fresh-machine install:** `tests/test_install_skills.sh` passes — in a sandbox HOME with
   an EMPTY `~/.claude/skills/` and a stubbed plugin cache, `bash install.sh` exits 0 and
   installs all ten skills.
2. **All ten resolve:** implicit in (1) — install cannot succeed unless every `skills:`
   entry and all three situational skills resolve; additionally, after install, each of the
   ten has `~/.claude/skills/<name>/SKILL.md` present (uppercase, verified by an exact-name
   listing so a case-insensitive filesystem cannot mask a lowercase file).
3. **Check reports OK:** `bash install.sh --check` exits 0 immediately after install (both
   in the sandbox test and on this machine after a real install).
4. **Drift detected:** the mutation cases in the sandbox test (edited file → DRIFT, removed
   file → MISSING, repo edit without reinstall → STALE) all exit nonzero naming the file.
5. **Existing suites still pass:** `tests/test_policy_hooks.sh`, `tests/test_cost_hook.sh`,
   `tests/test_dispatch_guard.sh` all pass unchanged.
6. **Vendored hygiene:** no `__pycache__`, `*.pyc`, `*.log`, `CLAUDE.md`,
   `integration_test_report_*.json`, `testing-summary.md`, `pattern-validation-results.md`,
   or `/Users/jay` string anywhere under `skills/` in the repo; every SKILL.md has `name:`
   and `description:`; the three `references/coding-standards.md` copies are hash-identical.
7. **Python tests (Option A only):** `python3 -m unittest discover` passes in the
   audit-requirements-document skill directory with pytest absent from the environment.
   Under Option B this criterion is vacuous — the repo's shell test suites in (1), (4), (5)
   are the operative "test suites still pass".
8. **Real machine:** on this machine, `bash install.sh` exits 0 and `bash install.sh
   --check` reports OK against the new manifest (which now includes skills entries).

## 8. Decisions needed at the gate

1. **audit-requirements-document: Option B (prompt-only, recommended) vs Option A (full
   Python repair).** See 3.8 for the tradeoff.
2. **secure-secrets rework direction:** confirm service-account-only auth and the removal of
   plaintext backup steps (both follow directly from the global security rules; flagged
   because this is the security-critical skill and the change alters its runtime behavior).
3. **Retiring the three writing-business-requirements subagent-prompt files and the
   examples.md stub:** they exist only on this machine; exclusion means they never reach a
   new machine. Recommended: exclude.
4. **Tier check:** dispatch sized this correctly as large; no re-tiering needed. The heavy
   items are secure-secrets and audit-requirements-document; everything else is mechanical.

## 9. Risks

- **Behavioral drift for live agents:** installing modernized skills over the live copies
  changes what the agents preload. Mitigation: every change is enumerated per skill above;
  the human gates the spec; `--check` plus the manifest make the change auditable; the
  installer backs up every overwritten file to the timestamped backup directory.
- **Sandbox fidelity:** the install test stubs the plugin cache; a real machine could still
  lack the superpowers plugin. Unchanged from today — the installer fails loudly on it, and
  README item 3 (rewritten) documents it as the remaining external dependency.
- **Shared-reference divergence:** three copies of coding-standards.md can drift apart in
  the repo; the new hash-identity validation converts silent divergence into a loud install
  failure.
- **Builder mechanics:** vendoring means creating ~15 files in the repo from reviewed
  content. The builder must do this with Read/Write tools (its policy forbids shell `cp`
  patterns that mutate via shell where blocked) — the plan will spell the per-file steps out.

## 10. Fixed constraints honored

- No package installs anywhere in the design (pytest eliminated under either option for
  anything an agent must run; `brew install` removed from secure-secrets; `python3` is only
  a dependency under Option A and is stdlib-only).
- No plan step will delete or move files via shell: exclusions happen by not vendoring;
  live-machine stale files are left in place, not deleted; installer rollback `rm` is script
  content run by the human installer, not an agent shell command.
- Standard-library-first: `unittest` if Python is kept; the installer remains
  bash+jq+shasum, all already required.
