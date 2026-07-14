# Handoff: land the complete Codex port

Date: 2026-07-14
Repository: `/Users/jay/Documents/agent-workforce`
Base: `main` at `ec75ceb` (also `origin/main`)
Feature branch: `codex/finishing-work` at `e547f83` (local only)
Recommended implementation model: GPT-5.6 Terra at high effort. The work is now
mechanical and bounded; use a stronger read-only reviewer for the final policy and
integration review.

## Outcome required

Land the existing Codex/ChatGPT plugin and companion-profile implementation on
`main`, updated to match the current eleven-role workforce (orchestrator plus ten
specialists, including the newly added debugger). Preserve the documented platform
limitations: this is a high-parity local Codex implementation, not a claim of exact
parity on every OpenAI surface.

Do not install anything into the real `~/.codex`, publish a marketplace entry through
a UI, delete branches, or remove unrelated files as part of this task. Repository
integration and pushing `main` are the target.

## Current frontier

- `main` and `origin/main` both point to `ec75ceb`.
- `codex/finishing-work` points to `e547f83`, one unmerged commit containing 74
  changed files, 4,855 insertions, and 24 deletions.
- Merge base is `c72fd0e`; the feature branch is one commit ahead and nine commits
  behind `main` (`git rev-list --left-right --count main...codex/finishing-work`
  returned `9 1`).
- No remote branch contains `e547f83`.
- The feature commit contains the Codex plugin manifest, marketplace metadata, 21
  generated custom-agent profiles plus 21 direct-launch profiles, launch/dispatch
  scripts, a companion installer, Codex role-policy enforcement, orchestration skill,
  parity documentation, closeout controls, and tests.
- The feature commit predates `agents/debugger.md`. Its Codex model policy explicitly
  contains only nine specialist roles and 21 profiles, so it must not be merged as-is.
- No implementation or integration work from this handoff has been performed. This
  handoff document is the only intentional new file and is currently untracked on
  `main`; carry it across the branch switch and include it with the eventual landing
  documentation.

## Preserve these unrelated working-tree files

They belong to the user and are outside the Codex port. Do not stage, edit, move,
delete, or clean them:

- `cta-antitrust-jingle.wav`
- `sing_antitrust_jingle.py`
- `scripts/__pycache__/render_codex_agents.cpython-313.pyc`

Use path-specific staging or `git add -u` plus explicit new Codex-port paths. Never use
`git add -A` while these files are present.

`docs/HANDOFF-2026-07-14-land-codex-port.md` is not unrelated: it is the requested
handoff artifact and should be included in the landing unless the human explicitly asks
to retire it after completion.

## Immediate next actions

1. Read this file and confirm the starting state:

   ```bash
   git status --short
   git rev-parse main origin/main codex/finishing-work
   git rev-list --left-right --count main...codex/finishing-work
   ```

2. Switch to the local-only feature branch and rebase its single commit onto `main`:

   ```bash
   git switch codex/finishing-work
   git rebase main
   ```

   Rebase is appropriate because the branch has never been pushed. If repository policy
   or the human prefers merge history, merging `main` into the feature branch is also
   valid; do not force-push either way.

3. Resolve the known overlaps as described below. Do not accept either side wholesale.

4. Add debugger parity to the Codex source policy, orchestration skill, generated
   profiles, tests, and current-facing documentation.

5. Run the targeted tests, then every `tests/*.sh` suite fresh after the last edit.

6. Read the complete final diff against `main`, commit only this work, fast-forward
   `main` to the verified branch, push `main`, and confirm `main == origin/main`.

## Known rebase/merge resolutions

### `README.md`

Keep both the current eleven-role/debugger wording from `main` and the cross-platform
Codex installation material from `e547f83`.

- The introduction must say eleven roles total and ten specialists.
- Diagnosis/debugging must remain in the workforce capability list.
- Add a debugger row to the local Codex roster.
- Keep the existing Claude live-plugin instructions and the new Codex/ChatGPT
  installation section.
- Keep all Claude, ChatGPT plugin, and Codex-profile validation commands in the
  shakedown checklist.

### `hooks/agent-team-policy.sh`

This is the highest-risk textual conflict. The resolved file must retain all of these:

- Current `main`: `debugger` uses `policy_readonly_runner` for Bash.
- Feature commit: active-model extraction and fail-closed
  `AGENT_TEAM_EXPECTED_MODEL` comparison.
- Feature commit: explicit shell denial for architect, researcher, scribe, and
  ticketer.
- Feature commit: `apply_patch` secret checks, deletion rejection, documentation-only
  paths for architect/scribe, builder allowance, and denial for other roles.
- Feature commit: specialists cannot call `Agent`, `spawn_agent`, or
  `collaboration.spawn_agent`.

The relevant Bash case should include:

```bash
verifier|reviewer|debugger) policy_readonly_runner ;;
architect|researcher|scribe|ticketer)
  block "shell access is not part of the $ROLE role" "$CMD" ;;
```

Add a Codex policy test proving the debugger cannot mutate through Bash or
`apply_patch`.

### `install.sh`

Both sides independently contain the same macOS Bash 3.2 empty-array fix. Keep one
clear comment and exactly this guarded iteration:

```bash
for existing in ${PROFILE_DIRS[@]+"${PROFILE_DIRS[@]}"}; do
```

Also keep the feature commit's calls to:

- `tests/test_chatgpt_plugin.sh`
- `tests/test_codex_profiles.sh`
- `tests/test_closeout_audit.sh`

### `tests/test_plugin_mode.sh`

Preserve both changes:

- Current `main` tests namespaced debugger policy routing.
- The feature commit validates the Claude manifest explicitly with
  `claude plugin validate --strict "$REPO/.claude-plugin/plugin.json"` because the
  repo will also contain `.claude-plugin/marketplace.json`.

### `agents/orchestrator.md`

Keep the current debugger, symptom-first routing, findings-ledger, factual-question,
relay-fidelity, and tense-scoping changes. Add the feature branch's completion-closeout
section without replacing those newer controls.

## Add debugger parity to the Codex port

### Source model policy

Add these two entries to `codex/model-policy.json`:

1. `agent_workforce_debugger`
   - role: `debugger`
   - variant: `default`
   - model: `gpt-5.6-terra`
   - effort: `high`
   - sandbox: `read-only`
   - approval policy: `never`
   - web search: `disabled`
   - purpose: diagnose symptoms and return evidence without applying a fix

2. `agent_workforce_debugger_deep`
   - role: `debugger`
   - variant: `upshift`
   - model: `gpt-5.6-sol`
   - effort: `high`
   - sandbox: `read-only`
   - approval policy: `never`
   - web search: `disabled`
   - purpose: second-pass or cross-system diagnosis

This follows the current Claude contract: Sonnet/high by default, Opus/high for a
second pass or cross-system failure, and no downshift. The expected profile total
becomes 23.

### Generated artifacts

After changing `codex/model-policy.json`, run:

```bash
python3 scripts/render_codex_agents.py
```

The generator reads `agents/debugger.md`. It should create and register all four new
generated files:

- `codex/agents/agent_workforce_debugger.toml`
- `codex/agents/agent_workforce_debugger_deep.toml`
- `codex/profiles/agent_workforce_debugger.config.toml`
- `codex/profiles/agent_workforce_debugger_deep.config.toml`

It must also update `codex/agent-workforce.config.toml`. Do not hand-edit generated
TOML instead of updating the JSON policy and rerunning the renderer.

### Orchestration and role contracts

Update these active files:

- `skills/agent-workforce/SKILL.md`
  - Include debugger in the skill description.
  - Route symptom-shaped requests to `agent_workforce_debugger` before assigning a
    build tier.
  - Use `agent_workforce_debugger_deep` on the second diagnosis of the same symptom
    or for a cross-system failure.
  - Carry over current-main safeguards: an evidence-backed findings ledger,
    fact-shaped questions are investigations rather than questions to the human,
    and the debugger's actionable first sentence is relayed faithfully.
- `skills/agent-workforce/references/roles.md`
  - Add the debugger's read-and-observe contract from `agents/debugger.md`.
  - Ensure debugger delivers root cause or ranked surviving hypotheses, evidence,
    unchecked scope, and the cheapest next check.
  - Preserve present-state versus historical tense discipline for debugger and ops.
- `skills/agent-workforce/references/model-policy.md`
  - Add both debugger profiles and their selection triggers.
- `skills/agent-workforce/references/surface-compatibility.md`
  - Change the active routing count from ten roles to eleven roles.
- `.codex-plugin/plugin.json`
  - Add debugging/diagnosis to the long role description.

### Current-facing documentation

Update current claims, not historical design records:

- `README.md`: eleven roles, ten specialists, debugger Codex row.
- `docs/chatgpt-codex-parity.md`: 23 custom profiles, 23 direct-launch profiles,
  eleven named roles, and debugger coverage.

Do not mechanically rewrite old plans/specs whose counts correctly describe an earlier
design state. Limit stale-count cleanup to current runtime, tests, plugin metadata, and
current parity/install documentation. Use this focused search:

```bash
rg -n "ten-role|Ten named roles|21 named|21 equivalent|length == 21|all 21|other nine|nine specialist" \
  README.md .codex-plugin codex docs/chatgpt-codex-parity.md \
  skills/agent-workforce tests/test_codex_profiles.sh
```

### Tests

Update `tests/test_codex_profiles.sh`:

- Expected profile and unique-name counts: 23.
- Expected roles include `debugger`.
- Installed custom-profile and direct-launch counts: 23.
- Assert the default and deep debugger profiles carry the expected model, effort,
  read-only sandbox, and hook role.
- Add policy coverage proving debugger mutation attempts fail closed.

Update `tests/test_chatgpt_plugin.sh` so the portable workforce skill must expose the
debugger/symptom-first route, rather than only checking the older role set.

Current `tests/test_dispatch_guard.sh` and `tests/test_plugin_mode.sh` already cover the
namespaced Claude debugger path on `main`; preserve that coverage through conflict
resolution.

## Verification state

### Proven before reconciliation

On 2026-07-14, commit `e547f83` was exported to an isolated `/tmp` directory and every
suite present on that commit ran with zero failed suites:

- `tests/test_chatgpt_plugin.sh`: PASS=15 FAIL=0
- `tests/test_closeout_audit.sh`: PASS=23 FAIL=0
- `tests/test_codex_profiles.sh`: PASS=22 FAIL=0
- `tests/test_cost_hook.sh`: passed=51 failed=0
- `tests/test_decision_discipline_drift.sh`: PASS=3 FAIL=0
- `tests/test_dispatch_guard.sh`: PASS=32 FAIL=0
- `tests/test_gap_loop_text.sh`: passed=16 failed=0
- `tests/test_install_skills.sh`: PASS=36 FAIL=0
- `tests/test_plugin_mode.sh`: PASS=20 FAIL=0
- `tests/test_policy_hooks.sh`: passed=191 failed=0

This proves the old 21-profile branch was internally green. It does not prove the rebased,
23-profile debugger-aware result.

### Must be rerun after the last edit

Run targeted checks first:

```bash
python3 scripts/render_codex_agents.py --check
bash tests/test_chatgpt_plugin.sh
bash tests/test_codex_profiles.sh
bash tests/test_closeout_audit.sh
bash tests/test_plugin_mode.sh
bash tests/test_dispatch_guard.sh
bash tests/test_policy_hooks.sh
```

Then run the entire repository suite and stop on the first failure:

```bash
for test_file in tests/*.sh; do
  echo "RUN $test_file"
  bash "$test_file" || exit 1
done
```

Finally run:

```bash
git diff --check
git status --short
```

Do not claim complete, merge, or push while any suite is red.

## Review focus

Read the complete final diff against `main`. Review handwritten/high-risk files first:

1. `hooks/agent-team-policy.sh`
2. `install-codex.sh`
3. `bin/agent-workforce-dispatch`
4. `scripts/render_codex_agents.py`
5. `codex/model-policy.json`
6. `skills/agent-workforce/SKILL.md` and its references
7. Codex and plugin tests
8. Closeout script and skill changes
9. Generated TOML (sample both debugger variants and rely on renderer `--check` for
   deterministic coverage of the full generated set)

Reject the integration if any of these are true:

- Debugger is absent from the Codex role/profile matrix.
- A debugger profile can mutate files or run a mutating shell command.
- The policy merge drops model-mismatch enforcement, patch restrictions, or the
  current debugger read-only policy.
- Current docs claim exact/full parity despite the documented OpenAI surface gaps.
- Tests only pass because profile counts or required roles were weakened.
- Unrelated jingle/audio/bytecode files are staged.

## Decisions and rationale

- **High parity, not exact parity.** The existing parity contract records real platform
  gaps: the tested in-thread tool cannot select custom profiles; there is no documented
  hard per-role turn limit; exact per-dispatch cost is unavailable; hosted ChatGPT Work
  cannot load local profiles/hooks; and desktop cannot set the parent composer model.
  Preserve these disclosures.
- **Two-part local installation remains required.** The plugin distributes the workflow
  skill; `install-codex.sh` installs user-scoped profiles and the policy runtime. Do not
  hide profile installation inside skill invocation.
- **Independent companion tasks remain the fallback.** A task-name-only child does not
  prove profile selection. Keep `bin/agent-workforce-dispatch` and its marker/audit
  validation.
- **Debugger gets two profiles, not a fast profile.** Current workforce policy forbids a
  debugging downshift and upshifts only for repeated or cross-system diagnosis.
- **Land the combined commit unless the human says to split it.** The branch includes
  closeout controls as well as Codex packaging, and the Codex orchestration skill depends
  on the closeout ledger/audit contract. Silently dropping those files would leave the
  branch internally inconsistent.
- **Do not install or publish during repository landing.** Tests exercise installers in a
  temporary `CODEX_HOME`; mutating the user's real Codex installation is a separate action.

## Land and push only after green verification and review

If the feature branch was rebased onto `main` and all work is committed:

```bash
git switch main
git merge --ff-only codex/finishing-work
git fetch --prune origin
git merge-base --is-ancestor origin/main main
git push origin main
git fetch --prune origin
git rev-parse main origin/main
```

The two final hashes must match. Do not delete `codex/finishing-work` without a separate
human cleanup decision.

## Required final report

Report:

- Landed commit hash and pushed branch.
- Exact targeted and full-suite outputs.
- Reviewer verdict and any repaired findings.
- Confirmation that 23 profiles exist and both debugger variants were generated.
- Confirmation that the three unrelated user files remain untracked and untouched.
- Remaining documented parity limitations.
- Closeout ledger: verification, review, documentation, memory, commit, deployment,
  integration, cleanup.
