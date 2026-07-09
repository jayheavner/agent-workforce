---
name: secure-secrets
description: >-
  Discover exposed secrets in a project directory and user configuration, then
  migrate them into 1Password using service-account authentication. Use both as
  an interactive credential-migration workflow (scan, confirm, store, verify,
  clean the source) and as an always-on secrets-handling discipline: reference
  every credential through an environment variable or an on-demand op read, never
  write or echo a secret value to any file, log, or transcript, with the single
  exception that secret values may be passed as arguments to op item create and
  op item edit because that is the vault's intended write path.
allowed-tools: [Bash(op:*), Bash(command:*), Bash(export:*), Bash(cat:*), Bash(git:*), Bash(curl:*), Bash(sed:*), Bash(cut:*), Bash(grep:*), Bash(echo:*), Read, Edit, Write, Glob, Grep, TodoWrite]
---
# Secure Secrets Skill

**Skill Name:** `secure-secrets`

**Invocation:** `/secure-secrets`

This skill has two jobs. First, it runs an interactive workflow that finds
credentials exposed in a project and in the user's shell configuration and moves
each one into 1Password. Second, it encodes the standing rules for handling
secrets that apply whenever this agent touches credentials, whether or not a
migration is underway:

- Reference every credential through an environment variable, or fetch it
  on demand with `op read`. Never inline a secret value in a command, script,
  config, or response.
- Never write a secret value to any file on disk, and never echo, print, or
  display a full secret value.
- The one permitted way to hand a secret value to a tool is passing it as an
  argument to `op item create` or `op item edit` — that is how the vault is
  written, and it is the only exception.

---

## Skill Instructions

When this skill is invoked, guide the user through a comprehensive secret
discovery and migration process.

### Phase 1: Prerequisites Check (service-account authentication only)

This skill authenticates to 1Password with a **service account only**. It never
uses 1Password desktop-app CLI integration, and it never installs software.

1. **Verify the 1Password CLI is on PATH**
   ```bash
   command -v op
   ```
   - If `op` is not found: **report this to the user and stop.** Do not install
     it, do not run `brew` or any package manager. State that the 1Password CLI
     must be installed by the human before this skill can run, then end.

2. **Authenticate with the service-account token**
   The token lives in `~/.op/service_account.token` and is exported into the
   environment variable the `op` CLI reads for service-account auth. Confirm the
   token is available and that the service account can reach its vault:
   ```bash
   export OP_SERVICE_ACCOUNT_TOKEN="$(cat ~/.op/service_account.token)"
   op vault list
   ```
   - The working vault for stored credentials is `ClaudeCodeAccess-Jay`.
   - If the token file is missing or `op vault list` fails, report the exact
     failure to the user and stop. Never fall back to desktop-app auth.

3. **Vaults outside the service account's access**
   If a credential belongs in a vault the service account cannot reach, do not
   switch authentication modes to reach it. Hand that specific step to the
   human: tell them the item name, fields, and target vault, and ask them to
   create the entry themselves. Then resume with the credentials you can handle.

### Phase 2: Comprehensive Secret Discovery

**Ask user first:** "Which directory should I scan for project files? (Press Enter for current directory: `$(pwd)`)"
- If user provides a path, use that directory
- If user presses Enter, use current working directory
- Validate the directory exists before proceeding

Systematically scan for secrets in two categories:

#### Category A: Project/Directory Scan (User-Specified or Current Directory)

**Critical Risk - Version Control**
Search for secrets committed to git in the target directory:
- Check git history, not just current files
- Look for: `.env` files, config files, CI/CD configs, infrastructure code, scripts, certificates, any files with credentials

**High Risk - Project Files**
Scan the target directory recursively:
- Environment files (any `.env*` pattern)
- Configuration files (`.json`, `.yaml`, `.yml`, `.xml`, `.conf`, `.config`, `.ini`, `.properties`, etc.)
- Docker/container files
- Certificate/key files (`.pem`, `.key`, `.crt`, `.p12`, `.pfx`, `.jks`)
- Private key patterns in file contents: `-----BEGIN.*PRIVATE KEY-----`, `-----BEGIN RSA PRIVATE KEY-----`, `-----BEGIN EC PRIVATE KEY-----`
- Scripts in any language
- Build configs
- Log files
- Temporary files
- Editor configs
- Documentation files (README, agent memory files, etc.)

#### Category B: User Configuration (Always Scanned)

**Medium Risk - System/User Configuration**
Check user configuration files (regardless of project directory):
- Shell configs: `~/.zshrc`, `~/.bashrc`, `~/.bash_profile`, `~/.profile`, `~/.zshenv`
- Shell history: `~/.bash_history`, `~/.zsh_history`
- Config directories: `~/.config/`, `~/.aws/`, `~/.kube/`, `~/.docker/`
- Application configs: `~/.gitconfig`, `~/.npmrc`, `~/.ssh/config`
- Custom scripts: `~/bin/`, `~/.local/bin/`

**SSH Key Security Check (Informational Only)**
Check `~/.ssh/` directory for unencrypted private keys:
- Look for: `id_rsa`, `id_ed25519`, `id_ecdsa`, `*.pem` files
- Test if keys are encrypted: `grep "ENCRYPTED" ~/.ssh/id_*`
- **DO NOT modify or migrate these keys** - SSH keys should remain as files
- **Report findings only:** Warn user if unencrypted keys are found
- **Recommendation:** Suggest adding passphrases to unencrypted keys via `ssh-keygen -p`
- **DO NOT scan `~/.ssh/` for content patterns** - only check for unencrypted keys

**Scope clarity:**
- Project scan: User-specified directory or current working directory (and all subdirectories)
- User config scan: Always scans user home directory configuration files listed above
- SSH keys: Check for encryption status only, report findings, do NOT migrate or modify
- Does NOT scan entire home directory
- Does NOT scan other unrelated projects or directories
- Does NOT scan `~/.ssh/` for content patterns (only checks encryption status)

**Create an inventory showing:**
- Location (file path)
- Risk level (one of the words CRITICAL, HIGH, MEDIUM)
- Secret type (API key, password, certificate, token, etc.)
- Service (what it's for)
- Value preview (first and last few characters only — this is the only form in
  which a secret value may ever be shown)

### Phase 3: Systematic Migration

For EACH credential discovered, process systematically. The verified 1Password
entry IS the backup: because every credential is stored and then confirmed with
`op read` before it is removed from the source, no separate on-disk copy is ever
made — writing secrets to disk is forbidden without exception.

#### Step 1: Ask Questions
For each credential, ask:
- **Is this actually a secret?** Present the context and ask user to confirm
  - Show file path, surrounding lines, and what was detected
  - Options:
    1. "Migrate this secret"
    2. "Skip (false positive)"
    3. "Skip (not needed)"
    4. "Delete (remove from file permanently)"
    5. "Already in 1Password (replace with reference)"

**If user chooses to skip:**
- Record in skipped credentials list with reason (false positive or not needed)
- Document in migration summary for audit trail
- Move to next credential

**If user chooses to delete:**
- Remove only the credential value from within the file (NOT the entire file)
- Read the file, remove/blank out the specific credential, write the file back
- Do NOT delete the entire file - only remove the secret value itself
- Record in deleted credentials list with:
  - File path
  - Line number
  - What was deleted (type/description, NOT the actual value)
  - Timestamp
  - Reason user wanted it deleted
- Document in migration summary for audit trail
- Move to next credential

**If user chooses "Already in 1Password":**
- Ask user: "What is the item name in 1Password?" (or let them search)
- Search 1Password for matching items:
  ```bash
  op item list | grep -i "search-term"
  ```
- Show matching items and ask user to select the correct one
- Ask: "Which vault is it in?" (or auto-detect from search results)
- Ask: "Which field contains the credential?" (default: `credential`, but could be `password`, `api_key`, etc.)
- Verify the credential matches by comparing the stored value to the source
  value without printing either one. Extract the source value from its file in
  the same command, then compare and report only match/no-match:
  ```bash
  FILEVAL="$(sed -n '42p' ~/.zshrc | cut -d'"' -f2)"
  [ "$(op read "op://ClaudeCodeAccess-Jay/Item Name/field_name")" = "$FILEVAL" ] \
    && echo MATCH || echo "NO MATCH"
  ```
- If values match: Skip migration, document the existing reference
- If values don't match: Warn user and ask what to do:
  1. "Use existing 1Password entry (values differ - may need rotation)"
  2. "Create new entry with different name"
  3. "Update existing entry with this value"
- Record in "Already in 1Password" list with:
  - File path where found
  - 1Password reference (op://Vault/Item/field)
  - Whether values matched
  - Action taken
- Move to next credential

**If user chooses to migrate (new entry), continue with:**
- **Which vault?** (default `ClaudeCodeAccess-Jay`; if a different vault is
  requested and the service account cannot reach it, hand that step to the
  human per Phase 1)
- **What should this item be named?** (suggest a clear name based on service)
- **Check for duplicates:** Search 1Password for similar items to avoid duplicates

#### Step 2: Test/Verify Before Storing
Before creating the 1Password entry:
- Attempt to test if the credential is valid
- Determine which service/tenant it belongs to
- Identify associated username or account

The secret is never typed as a literal into any command. Populate the shell
variable by extracting it from the source file in the same command, then
reference the variable:
```bash
VALUE="$(sed -n '42p' ~/.zshrc | cut -d'"' -f2)"
curl -H "Authorization: Bearer $VALUE" https://api.service.com/user
```

This helps:
- Confirm validity
- Identify correct service
- Determine proper naming

**Document the test:** Record what test was performed and the result for the testing report.

#### Step 3: Create 1Password Entry
Based on user's answers:

```bash
op item create \
  --vault ClaudeCodeAccess-Jay \
  --category "API Credential" \
  --title "User Provided Name" \
  credential="$VALUE" \
  --tags "claude code"
```

Passing the value to `op item create` is the one sanctioned way to hand a secret
to a tool. Use consistent field naming:
- Single tokens: `credential` field
- Key pairs: `api_key` and `api_secret` fields
- Passwords: `username` and `password` fields

#### Step 4: Test 1Password Integration
After creating the entry, immediately test that it can be retrieved. This is an
existence check only — discard the value so it never reaches stdout:

```bash
op read "op://ClaudeCodeAccess-Jay/Item Name/field_name" >/dev/null \
  && echo "retrieved OK" || echo "retrieval FAILED"
```

If the credential was tested in Step 2, re-run that test using the 1Password
reference (assign to a shell variable; never print it):
```bash
VALUE="$(op read "op://ClaudeCodeAccess-Jay/Item Name/credential")"
curl -H "Authorization: Bearer $VALUE" https://api.service.com/user
```

**Success criteria:**
- `op read` command successfully retrieves the credential
- If applicable, the credential works in its actual use case
- Document test results (pass/fail, not the value) for the testing report

**On failure:**
- Verify 1Password reference syntax
- Check vault access permissions
- Confirm the credential value was stored correctly
- Fix the issue and re-test
- **Do NOT proceed to Phase 4** until this credential works via 1Password
- Troubleshoot with user; only move to next credential after successful validation

**Critical:** The original credential remains in the config file until testing
passes. This is what makes the verified vault entry a sufficient backup — the
source is not touched until the vault copy is proven readable.

#### Step 5: Document Reference
Record the 1Password reference (the reference is safe to write; the value is not):
```
op://ClaudeCodeAccess-Jay/Item Name/field_name
```

#### Step 6: Track for Later
Maintain lists of:
- Credentials needing rotation (by risk level)
- Duplicate credentials to investigate
- Security issues discovered
- Test results (passed/failed/skipped)
- **Skipped credentials:** File path, reason (false positive or not needed), who skipped, when
- **Deleted credentials:** File path, line number, what was deleted (type/description only), timestamp, reason
- **Already in 1Password:** File path, 1Password reference, whether values matched, action taken

### Phase 4: Update Configuration Files

**IMPORTANT:** Only remove secrets from files AFTER they have been successfully
stored in and re-read from 1Password in Phase 3. There is no plaintext backup
step: the verified vault entry is the backup, and copying a secret into a
`reports/` folder or anywhere else on disk is forbidden.

1. **Update shell configs**
   - Remove hardcoded credential values
   - Replace with a comment showing how to fetch from 1Password on demand

   Example: replace a hardcoded `export SOME_TOKEN="literal-value"` line with a
   comment that documents the retrieval command instead:
   ```bash
   # SOME_TOKEN - fetch on demand:
   #   export SOME_TOKEN="$(op read "op://ClaudeCodeAccess-Jay/Some Token/credential")"
   ```

2. **Update project files**
   - Remove hardcoded secrets
   - Add to `.gitignore` if needed
   - Document 1Password references in comments

### Phase 5: Generate Documentation

Create documentation that records references and decisions only. No document
produced by this skill may contain a secret value — only `op://` references,
risk levels, and audit metadata.

**Reports** (store in a `reports/` folder):
- Migration summaries
- Credential rotation plans
- Testing reports (documenting what was tested during migration)
- Quick reference guides (user-specific credential access patterns)
- Security audit reports
- Inventory reports

#### 1. Migration Summary (→ `reports/MIGRATION_SUMMARY.md`)
- **Scan scope:** Exact directories and files that were scanned, with timestamp
- **Total secrets found:** Count and breakdown
- **Breakdown by risk level:** CRITICAL, HIGH, MEDIUM
- **Breakdown by type:** API keys, tokens, passwords, certificates, etc.
- **What was migrated:** Where each credential was stored in 1Password (`op://` reference + original file path)
- **What was skipped:** File path, reason, timestamp, risk level
- **What was already in 1Password:** File path, `op://` reference, whether values matched, action taken, timestamp
- **What was deleted:** File path, line number, type/description (NOT the value), timestamp, reason, risk level

#### 2. Credential Rotation Plan (→ `reports/CREDENTIALS_ROTATION_PLAN.md`)
For each credential, document:
- **Priority:** Based on risk level
  - CRITICAL (git-committed): IMMEDIATE rotation required
  - HIGH: Rotate promptly
  - MEDIUM: Rotate as convenient
- **Service:** Where to generate new credential
- **Steps:** How to rotate
- **Impact:** What depends on this credential
- **Status:** Not rotated / In progress / Rotated

#### 3. Testing Report (→ `reports/TESTING_REPORT.md`)
- **Pre-migration tests:** What was tested before storing (validity, service identification)
- **Post-migration tests:** Verification that `op read` works and credentials function
- **Test results:** Pass/fail/skipped status per credential (results only, never values)
- **Failures and resolutions:** Issues encountered and how they were resolved
- **Untested credentials:** Which credentials could not be tested and why

#### 4. Quick Reference (→ `reports/CREDENTIAL_QUICK_REFERENCE.md`)
List all credentials with their 1Password references (references only):
```
Okta token:  op read "op://ClaudeCodeAccess-Jay/Okta API Token/credential"
Jira token:  op read "op://ClaudeCodeAccess-Jay/Jira API Token/credential"
```

### Phase 6: Validate Migration Success

After all credentials are migrated and configuration files updated:

1. **Verify documentation completeness**
   - All four documents generated
   - Testing report shows all credentials were validated
   - Any failures or issues are documented with resolutions

2. **Confirm configuration safety**
   - No hardcoded secrets remain in any files
   - 1Password references are correctly formatted
   - All credentials tested and working

3. **Review with user**
   - Show summary of what was accomplished
   - Highlight any credentials that could not be tested
   - Emphasize critical rotation requirements
   - Confirm user understands how to use `op read` for credential retrieval

There is no backup-cleanup step, because no plaintext backup was ever created.

### Important Behaviors

**Security:**
- NEVER write credential values to any file (scripts, configs, logs, reports)
- ALWAYS use 1Password references or fetch on-demand with `op read`
- The ONLY place a secret value may be shown is a value preview of the first and
  last few characters, used to help the user confirm identity. Never display a
  full value.

**Systematic Process:**
- Process credentials ONE AT A TIME
- Ask questions for EVERY credential
- Test BEFORE removing from config files
- Don't skip or batch without user approval
- Maintain consistency in naming and organization
- Only proceed to Phase 4 (config file updates) when ALL credentials are tested and working

**Risk Assessment:**
- Prioritize by exposure risk
- Git-committed secrets are CRITICAL priority
- Clearly communicate rotation urgency

**Transparency:**
- Show what you're doing at each step
- Explain why (testing helps identify service, etc.)
- Get approval before making changes

---

## Worked Example (one credential)

```
User invokes: /secure-secrets

Phase 1: Checking prerequisites (service-account auth only)...
  command -v op            -> op is on PATH   (if absent, report and stop; do not install)
  export the service-account token from ~/.op/service_account.token
  op vault list            -> ClaudeCodeAccess-Jay visible

Phase 2: Scanning project + user config...
  Found in ~/.zshrc (line 42)
    Risk level: MEDIUM
    Type: API token
    Service: Okta (internal tenant)
    Value preview: 00ab...z123   (first/last chars only)

Phase 3: Migrating this credential
  Confirm it is a real secret -> user: "Migrate"
  Test validity (value extracted from the source file in the same command,
  never typed as a literal):
    VALUE="$(sed -n '42p' ~/.zshrc | cut -d'"' -f2)"
    curl -s -H "Authorization: SSWS $VALUE" https://cta.okta.com/api/v1/users/me  -> valid
  Store in the vault (value passed only to op item create):
    op item create --vault ClaudeCodeAccess-Jay --category "API Credential" \
      --title "Okta API Token - Internal Tenant" credential="$VALUE" --tags "claude code"
  Verify it round-trips (value discarded to /dev/null, never printed):
    op read "op://ClaudeCodeAccess-Jay/Okta API Token - Internal Tenant/credential" >/dev/null && echo "retrieved OK"
  Only now edit ~/.zshrc: replace the hardcoded value with an op read comment.

Reference recorded:
  op read "op://ClaudeCodeAccess-Jay/Okta API Token - Internal Tenant/credential"
```

---

## Error Handling

**1Password CLI not installed:**
```
The 1Password CLI (op) is not on PATH. This skill does not install software.
Please install the 1Password CLI, then re-run /secure-secrets.
```
(Report and stop. Do not run brew or any package manager.)

**Service-account token missing or vault unreachable:**
```
Could not authenticate the 1Password service account
(~/.op/service_account.token missing, or `op vault list` failed).
Fix the service-account token and re-run. Never fall back to desktop-app auth.
```

**Target vault outside service-account access:**
```
The requested vault is not reachable by the service account. Handing this
credential to you: create an item named "<name>" with field "<field>" in vault
"<vault>", then tell me the op:// reference so I can finish the source cleanup.
```

**Credential test fails:**
```
Warning: Could not verify this credential.
It may be invalid, expired, or for a service I cannot test.
Proceed with storing in 1Password? (yes/no)
```

**User wants to skip a credential:**
```
Why are you skipping this?
1. False positive - not actually a secret
2. Not needed - will handle separately
3. Other (specify)
```

---

## Success Criteria

Migration is successful when:
1. All secrets discovered and inventoried
2. All secrets migrated to 1Password (or explicitly skipped)
3. All credentials tested and working via 1Password BEFORE config file updates
4. Configuration files updated (no hardcoded secrets)
5. Documentation generated (rotation plan, testing report, quick reference), containing references only
6. User understands how to fetch credentials with `op read`
7. Rotation plan created with clear priorities

---

## Notes for Future Sessions

After this skill completes, future sessions should:
- Use `op read` to fetch credentials on-demand
- NEVER write credential values to files
- Reference credentials as: `op://ClaudeCodeAccess-Jay/Item/field`
- Authenticate with the service account only, never desktop-app integration
