# op-migration: detailed workflow

## vault-config (pack-local, not core policy)

This pack needs two values that are 1Password-deployment-specific, not
framework policy: the vault name credentials are stored in, and the path to
the service-account token. They are **not** `policy:<key>` tokens — they
don't appear in `policy/KEYS.md`, and they never will, because that
registry stays vendor-free (a project with no 1Password pack installed has
no reason to carry a 1Password vault name in its policy file).

Instead, resolve them from this pack's own `vault-config` entry, and state
the resolved value and its source before using it:

- **Vault name** — the vault that stores migrated credentials. There is
  no portable default: the consuming project or user records the vault
  name (e.g. a project-local note this pack's installer or user adds).
  If none is recorded, do not guess — ask for the vault name (or list
  the service account's reachable vaults with `op vault list` and have
  the human pick) and state which you used.
- **Token path** — where the service-account token lives on disk.
  Default: `~/.op/service_account.token`. Same override rule.

This is a deliberate, narrow exception to "keys come only from
`policy/KEYS.md`": it is pack-local config for a single vendor integration,
not a cross-cutting framework policy value.

## Phase 1: Prerequisites (service-account auth only)

1. `command -v op` — if missing, report to the user and stop. Do not
   install `op` via `brew` or any package manager.
2. Authenticate with the service-account token:
   ```bash
   export OP_SERVICE_ACCOUNT_TOKEN="$(cat <token-path-from-vault-config>)"
   op vault list
   ```
   If the token file is missing or `op vault list` fails, report the exact
   failure and stop. Never fall back to desktop-app auth.
3. If a credential belongs in a vault the service account cannot reach,
   don't switch auth modes to get there — hand that item (name, fields,
   target vault) to the human, then resume with the credentials you can
   handle.

## Phase 2: Discovery

Scope and categories follow `handling-secrets` (project directory + named
config files; user shell/config files also scanned; `~/.ssh/` checked for
encryption status only, never content-scanned). Build an inventory:

- Location (file path)
- Risk level (CRITICAL / HIGH / MEDIUM — see SKILL.md)
- Secret type (API key, password, certificate, token, etc.)
- Service (what it's for)
- Value preview (first/last few characters only)

## Phase 3: Per-credential migration

For each credential, in order:

1. **Confirm it's real** — show file path, surrounding lines, and what was
   detected. Options: migrate / skip (false positive) / skip (not needed)
   / delete from source / already in 1Password.
   - Skip → record file path + reason in the migration summary, move on.
   - Delete → remove only the value from within the file (never the whole
     file); record file path, line, what was deleted (type only, never the
     value), timestamp, reason.
   - Already in 1Password → ask for the item/vault/field, then verify by
     comparing the stored value to the source value without printing
     either: extract the source value and compare in one command,
     reporting only match/no-match. Record file path, `op://` reference,
     match result, action taken.
2. **Test/verify before storing** — attempt to validate the credential
   (which service, which account) by reading the value into a shell
   variable and using it in the same command; never type it as a literal.
   Document what was tested and the result (not the value).
3. **Create the 1Password entry** — the value is passed only to
   `op item create` (the sanctioned write path):
   ```bash
   op item create --vault "<vault-from-vault-config>" \
     --category "API Credential" --title "User Provided Name" \
     credential="$VALUE" --tags "claude code"
   ```
   Use the field-naming conventions in SKILL.md.
4. **Re-read to verify** — existence check only, value discarded:
   ```bash
   op read "op://<vault>/Item Name/field_name" >/dev/null \
     && echo "retrieved OK" || echo "retrieval FAILED"
   ```
   If Phase 3 step 2 tested the credential functionally, re-run that same
   test using the `op read` value (assigned to a variable, never printed).
   On failure: don't proceed to Phase 4 for this credential — fix and
   re-test, or troubleshoot with the user.

## Phase 4: Update source (only after Phase 3 verification passes)

Remove the hardcoded value from its file and replace it with a comment
showing the on-demand retrieval command:

```bash
# SOME_TOKEN - fetch on demand:
#   export SOME_TOKEN="$(op read "op://<vault>/Some Token/credential")"
```

There is no plaintext backup step at any point — the verified vault entry
is the backup, so nothing is ever copied to a `reports/` folder or
anywhere else on disk.

## Phase 5: The four reports

Store all four in a `reports/` folder. Every report contains references,
risk levels, and audit metadata only — never a secret value.

1. **`reports/MIGRATION_SUMMARY.md`** — scan scope + timestamp; counts by
   risk level and type; what was migrated (`op://` reference + original
   path); what was skipped/already-present/deleted, each with reason and
   timestamp.
2. **`reports/CREDENTIALS_ROTATION_PLAN.md`** — per credential: priority
   from risk level (CRITICAL = immediate, HIGH = promptly, MEDIUM = as
   convenient), where to regenerate it, rotation steps, what depends on
   it, status.
3. **`reports/TESTING_REPORT.md`** — pre- and post-migration test results
   per credential (pass/fail/skipped, never the value), failures and how
   they were resolved, any credential that couldn't be tested and why.
4. **`reports/CREDENTIAL_QUICK_REFERENCE.md`** — every credential as an
   `op read` command using its reference, e.g.
   `op read "op://<vault>/Okta API Token/credential"`.

## Phase 6: Validate migration success

Confirm all four reports exist, the testing report shows every credential
was validated (or explains why not), no hardcoded secret remains in any
file, and the user understands how to retrieve credentials with `op read`.
Review the summary with the user and highlight any untested credential or
urgent rotation.
